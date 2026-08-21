import os
import re
import json
import time
import threading
import logging
from datetime import datetime, timezone
from pathlib import Path

import docker
import markdown
import pyte
from flask import Flask, render_template, jsonify, request, redirect, url_for

# -------- config --------
MAX_LEVEL          = int(os.environ.get("MAX_LEVEL", "10"))
CURRENT_PREFIX     = os.environ.get("EXERCISE_CONTAINER", "exercise-current")
PREWARM_PREFIX     = "exercise-prewarm"
IMAGE_PREFIX       = os.environ.get("EXERCISE_IMAGE_PREFIX", "interview/exercise-")
NETWORK            = os.environ.get("INTERVIEW_NETWORK", "interview_net")
PREWARM_NETWORK    = "interview_prewarm_net"
STATE_FILE         = Path(os.environ.get("STATE_FILE", "/state/level.txt"))
RESULTS_FILE       = Path(os.environ.get("RESULTS_FILE", "/state/results.json"))
STARTED_FILE       = Path(os.environ.get("STARTED_FILE", "/state/started_at.txt"))
DURATION_SECONDS   = int(os.environ.get("DURATION_SECONDS", "10800"))
HISTORY_VOLUME     = os.environ.get("HISTORY_VOLUME", "dba-interview-history")
HISTORY_DIR        = Path(os.environ.get("HISTORY_DIR", "/state/history"))
EXERCISES_DIR      = Path("/exercises")
LABEL              = "dba-interview"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("controller")

app = Flask(__name__)
client = docker.from_env()
_lock = threading.Lock()


# -------- level state --------
def get_level() -> int:
    if not STATE_FILE.exists():
        return 1
    try:
        return max(1, int(STATE_FILE.read_text().strip() or "1"))
    except ValueError:
        return 1


def set_level(n: int) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(str(n))


def get_started_at() -> int | None:
    if not STARTED_FILE.exists():
        return None
    try:
        return int(STARTED_FILE.read_text().strip())
    except ValueError:
        return None


def ensure_started_at() -> int:
    """Return the interview start epoch; create it on first call."""
    ts = get_started_at()
    if ts is not None:
        return ts
    ts = int(time.time())
    STARTED_FILE.parent.mkdir(parents=True, exist_ok=True)
    STARTED_FILE.write_text(str(ts))
    return ts


def clear_started_at() -> None:
    if STARTED_FILE.exists():
        STARTED_FILE.unlink()


def clear_results() -> None:
    if RESULTS_FILE.exists():
        RESULTS_FILE.unlink()


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_results() -> dict:
    if not RESULTS_FILE.exists():
        return {}
    try:
        return json.loads(RESULTS_FILE.read_text())
    except (json.JSONDecodeError, ValueError):
        return {}


def save_results(results: dict) -> None:
    RESULTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    RESULTS_FILE.write_text(json.dumps(results, indent=2, sort_keys=True))


def record_start(level: int) -> None:
    r = load_results()
    key = str(level)
    if key not in r:
        r[key] = {"started": _now(), "attempts": 0, "passed": False}
        save_results(r)


def record_attempt(level: int, passed: bool) -> None:
    r = load_results()
    key = str(level)
    entry = r.setdefault(key, {"started": _now(), "attempts": 0, "passed": False})
    entry["attempts"] = entry.get("attempts", 0) + 1
    entry["last_attempt"] = _now()
    if passed and not entry.get("passed"):
        entry["passed"] = True
        entry["passed_at"] = _now()
    save_results(r)


def level_dir(level: int) -> Path | None:
    """Find the directory for a given level (matches NN-*)."""
    prefix = f"{level:02d}-"
    for p in sorted(EXERCISES_DIR.iterdir()) if EXERCISES_DIR.exists() else []:
        if p.is_dir() and p.name.startswith(prefix):
            return p
    return None


def read_nodes(level: int) -> list[str]:
    """One line per node name in exercises/NN-*/nodes.txt; default ['mongod']."""
    d = level_dir(level)
    if not d:
        return ["node1"]
    f = d / "nodes.txt"
    if not f.exists():
        return ["node1"]
    names = [ln.strip() for ln in f.read_text().splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
    return names or ["node1"]


def read_readme(level: int) -> tuple[str, str]:
    d = level_dir(level)
    if not d:
        return (f"Question {level}", "_No README found._")
    md_path = d / "README.md"
    if not md_path.exists():
        return (d.name, "_No README found._")
    text = md_path.read_text()
    lines = text.splitlines()
    if lines and lines[0].startswith("#"):
        title = lines[0].lstrip("# ").strip()
        body_md = "\n".join(lines[1:]).lstrip("\n")
    else:
        title = d.name
        body_md = text
    body_html = markdown.markdown(body_md, extensions=["fenced_code", "tables"])
    return (title, body_html)


# -------- docker management --------
def image_name(level: int) -> str:
    return f"{IMAGE_PREFIX}{level:02d}"


def image_exists(level: int) -> bool:
    try:
        client.images.get(image_name(level))
        return True
    except docker.errors.ImageNotFound:
        return False


def container_name(node: str) -> str:
    """Candidate-visible (current) container name. nginx routes to this."""
    return f"{CURRENT_PREFIX}-{node}"


def prewarm_name(node: str) -> str:
    return f"{PREWARM_PREFIX}-{node}"


def first_node_container(level: int) -> str:
    return container_name(read_nodes(level)[0])


def _stop_by_prefix(prefix: str) -> None:
    for c in client.containers.list(all=True):
        if c.name == prefix or c.name.startswith(prefix + "-"):
            try:
                log.info("stopping container %s", c.name)
                c.remove(force=True)
            except docker.errors.APIError as e:
                log.warning("error stopping %s: %s", c.name, e)


def stop_current() -> None:
    _stop_by_prefix(CURRENT_PREFIX)


def stop_prewarm() -> None:
    _stop_by_prefix(PREWARM_PREFIX)


def stop_exercise() -> None:
    stop_current()
    stop_prewarm()


def ensure_networks() -> None:
    for n in (NETWORK, PREWARM_NETWORK):
        try:
            client.networks.get(n)
        except docker.errors.NotFound:
            client.networks.create(n, driver="bridge")


def _spawn(level: int, role: str) -> str | None:
    """Spawn containers for `level` with `role` in ('current', 'prewarm').
    Returns None on success, error message otherwise."""
    ensure_networks()
    if role == "current":
        net, name_fn = NETWORK, container_name
        _stop_by_prefix(CURRENT_PREFIX)
    else:
        net, name_fn = PREWARM_NETWORK, prewarm_name
        _stop_by_prefix(PREWARM_PREFIX)
    img = image_name(level)
    try:
        client.images.get(img)
    except docker.errors.ImageNotFound:
        return f"Image {img} is not built. Run ./build.sh first."

    nodes = read_nodes(level)
    for node in nodes:
        name = name_fn(node)
        log.info("starting %s (role=%s, hostname=%s) from image %s",
                 name, role, node, img)
        try:
            client.containers.run(
                img,
                name=name,
                hostname=node,
                network=net,
                detach=True,
                auto_remove=True,
                privileged=True,
                cgroupns="host",
                tmpfs={"/run": "", "/run/lock": "", "/tmp": ""},
                environment={
                    "NODE_NAME": node,
                    "NODE_INDEX": str(nodes.index(node)),
                    "NODE_PEERS": ",".join(nodes),
                    "LEVEL": str(level),
                },
                volumes={
                    HISTORY_VOLUME: {"bind": "/var/log/history", "mode": "rw"},
                    "/sys/fs/cgroup": {"bind": "/sys/fs/cgroup", "mode": "rw"},
                },
                labels={LABEL: "true", "level": str(level), "node": node, "role": role},
            )
        except docker.errors.APIError as e:
            _stop_by_prefix(CURRENT_PREFIX if role == "current" else PREWARM_PREFIX)
            return f"docker run failed for {name}: {e}"
    return None


def start_exercise(level: int) -> str | None:
    return _spawn(level, "current")


def prewarm_next(level: int) -> None:
    """Best-effort prewarm of `level+1` in a background thread."""
    next_level = level + 1
    if next_level > MAX_LEVEL or not image_exists(next_level):
        return
    try:
        err = _spawn(next_level, "prewarm")
        if err:
            log.warning("prewarm of level %d failed: %s", next_level, err)
        else:
            log.info("prewarm of level %d kicked off", next_level)
    except Exception:
        log.exception("prewarm thread crashed")


def promote_prewarm(level: int) -> bool:
    """If prewarmed containers exist for `level`, move them onto the
    candidate-visible network and rename them to the current-prefix.
    Returns True if promotion succeeded, False if we must fresh-spawn."""
    nodes = read_nodes(level)
    promoted = []
    for node in nodes:
        try:
            c = client.containers.get(prewarm_name(node))
            promoted.append((node, c))
        except docker.errors.NotFound:
            return False

    stop_current()
    try:
        main_net = client.networks.get(NETWORK)
        pre_net = client.networks.get(PREWARM_NETWORK)
    except docker.errors.NotFound:
        return False

    for node, c in promoted:
        try:
            pre_net.disconnect(c, force=True)
        except docker.errors.APIError as e:
            log.warning("disconnect %s from prewarm net failed: %s", c.name, e)
        try:
            main_net.connect(c, aliases=[node])
        except docker.errors.APIError as e:
            log.warning("connect %s to main net failed: %s", c.name, e)
            stop_current()
            stop_prewarm()
            return False
        try:
            c.rename(container_name(node))
        except docker.errors.APIError as e:
            log.warning("rename %s failed: %s", c.name, e)
            stop_current()
            stop_prewarm()
            return False
    log.info("promoted prewarm to current for level %d (%d nodes)", level, len(promoted))
    return True


def run_check(level: int) -> tuple[bool, str]:
    first = first_node_container(level)
    try:
        c = client.containers.get(first)
    except docker.errors.NotFound:
        return False, "exercise container is not running"
    rc, out = c.exec_run(["/usr/local/bin/check.sh"], demux=False)
    text = out.decode("utf-8", errors="replace") if out else ""
    return (rc == 0), text.strip()


# -------- routes --------
@app.route("/")
def index():
    level = get_level()
    if level > MAX_LEVEL or not image_exists(level):
        return render_template("done.html", max_level=MAX_LEVEL)
    # Lazy-start the current exercise if it isn't running (probed via node1).
    first = first_node_container(level)
    try:
        client.containers.get(first)
    except docker.errors.NotFound:
        with _lock:
            try:
                client.containers.get(first)
            except docker.errors.NotFound:
                err = start_exercise(level)
                if err:
                    return render_template("error.html", message=err), 500
                threading.Thread(target=prewarm_next, args=(level,), daemon=True).start()
    record_start(level)
    started_at = ensure_started_at()
    title, body = read_readme(level)
    nodes = read_nodes(level)
    return render_template(
        "index.html",
        level=level,
        max_level=MAX_LEVEL,
        title=title,
        body=body,
        nodes=nodes,
        started_at=started_at,
        duration_seconds=DURATION_SECONDS,
    )


@app.route("/check", methods=["POST"])
def check():
    """Run the level's check, record pass/fail, and unconditionally advance.
    The candidate sees no pass/fail signal — the interviewer dashboard does."""
    with _lock:
        level = get_level()
        if level > MAX_LEVEL:
            return jsonify(submitted=True, done=True)
        passed, _ = run_check(level)
        record_attempt(level, passed)
        new_level = level + 1
        set_level(new_level)
        if new_level > MAX_LEVEL or not image_exists(new_level):
            stop_exercise()
            return jsonify(submitted=True, done=True)
        if not promote_prewarm(new_level):
            start_exercise(new_level)
        threading.Thread(target=prewarm_next, args=(new_level,), daemon=True).start()
        return jsonify(submitted=True, done=False)


@app.route("/reset", methods=["POST"])
def reset():
    with _lock:
        set_level(1)
        clear_started_at()
        clear_results()
        stop_exercise()
        err = start_exercise(1)
        if not err:
            threading.Thread(target=prewarm_next, args=(1,), daemon=True).start()
    if err:
        return jsonify(ok=False, error=err), 500
    return redirect(url_for("index"))


@app.route("/healthz")
def healthz():
    return "ok"


# -------- interviewer view --------
_SCRIPT_BANNER_RE = re.compile(rb"^Script (started|done).*$\r?\n?", re.MULTILINE)


def _clean_typescript(data: bytes) -> str:
    """Replay the typescript through a virtual VT100 so backspaces, cursor
    moves, and in-place line redraws (mongosh readline editing) resolve to
    the *visible* text — what the candidate actually saw on screen.
    Input is raw bytes so CRs survive (Python text mode would translate them)."""
    data = _SCRIPT_BANNER_RE.sub(b"", data)

    # Tall enough to hold a full session without scroll loss; pyte scrolls
    # off the top once full, so we use HistoryScreen and harvest the
    # scrollback too.
    screen = pyte.HistoryScreen(140, 50, history=20000, ratio=1.0)
    stream = pyte.ByteStream(screen)
    stream.feed(data)

    out_lines: list[str] = []
    # Scrolled-off history (oldest first).
    for entry in screen.history.top:
        line = "".join(ch.data for ch in entry.values()).rstrip()
        out_lines.append(line)
    # Currently visible screen.
    for line in screen.display:
        out_lines.append(line.rstrip())

    while out_lines and not out_lines[0].strip():
        out_lines.pop(0)
    while out_lines and not out_lines[-1].strip():
        out_lines.pop()
    return "\n".join(out_lines)


def _read_sessions(level: int) -> list[dict]:
    """One transcript per node per level. Coalesces the legacy per-PID
    files (`<node>-session-<pid>.typescript`) and the current per-node
    files (`<node>.typescript`) into a single chronological block per node:
    {"node": str, "mtime": iso, "text": str}."""
    level_dir = HISTORY_DIR / f"level-{level}"
    if not level_dir.exists():
        level_dir = HISTORY_DIR / f"level-{level:02d}"
    if not level_dir.exists():
        return []

    by_node: dict[str, list[tuple[float, str]]] = {}
    for f in level_dir.iterdir():
        if not f.is_file() or not f.name.endswith(".typescript"):
            continue
        m = re.match(r"^(?P<node>.+?)(?:-session-\d+)?\.typescript$", f.name)
        node = m.group("node") if m else f.stem
        try:
            raw = f.read_bytes()
        except OSError:
            continue
        text = _clean_typescript(raw)
        if not text:
            continue
        by_node.setdefault(node, []).append((f.stat().st_mtime, text))

    sessions: list[dict] = []
    for node, chunks in by_node.items():
        chunks.sort(key=lambda t: t[0])
        text = "\n".join(c for _, c in chunks).strip()
        if not text:
            continue
        last = max(t for t, _ in chunks)
        mtime = datetime.fromtimestamp(last, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        sessions.append({"node": node, "mtime": mtime, "text": text})
    sessions.sort(key=lambda s: s["node"])
    return sessions


@app.route("/interviewer/")
def interviewer():
    results = load_results()
    current = get_level()
    rows = []
    for n in range(1, MAX_LEVEL + 1):
        d = level_dir(n)
        title = d.name if d else f"Question {n}"
        if d and (d / "README.md").exists():
            first = (d / "README.md").read_text().splitlines()[0].lstrip("# ").strip()
            if first:
                title = first
        r = results.get(str(n), {})
        passed = r.get("passed", False)
        attempts = r.get("attempts", 0)
        left_behind = n < current
        if passed:
            outcome = "passed"
        elif left_behind:
            outcome = "failed"
        elif attempts:
            outcome = "attempted"
        else:
            outcome = "pending"
        rows.append({
            "level": n,
            "title": title,
            "passed": passed,
            "outcome": outcome,
            "attempts": attempts,
            "started": r.get("started", ""),
            "last_attempt": r.get("last_attempt", ""),
            "passed_at": r.get("passed_at", ""),
            "is_current": n == current,
            "sessions": _read_sessions(n),
        })
    started_at = get_started_at()
    if started_at is not None:
        elapsed = int(time.time()) - started_at
        time_used_h = elapsed / 3600
        overrun_s = max(0, elapsed - DURATION_SECONDS)
    else:
        time_used_h = 0.0
        overrun_s = 0
    return render_template(
        "interviewer.html",
        rows=rows,
        max_level=MAX_LEVEL,
        current_level=current,
        started_at=started_at,
        duration_seconds=DURATION_SECONDS,
        time_used_h=time_used_h,
        overrun_s=overrun_s,
    )
