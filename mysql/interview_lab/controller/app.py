import os
import re
import base64
import hmac
import json
import secrets
import shutil
import tempfile
import time
import threading
import logging
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path

import docker
import markdown
import pyte
from flask import Flask, render_template, jsonify, request, redirect, url_for

# -------- config --------
# 11 questions. The default used to be 10 while compose said 11, so running
# the controller outside compose silently dropped the last question.
MAX_LEVEL          = int(os.environ.get("MAX_LEVEL", "11"))
CURRENT_PREFIX     = os.environ.get("EXERCISE_CONTAINER", "mysql-exercise-current")
PREWARM_PREFIX     = os.environ.get("EXERCISE_PREWARM", "mysql-exercise-prewarm")
IMAGE_PREFIX       = os.environ.get("EXERCISE_IMAGE_PREFIX", "mysqlinterview/exercise-")
NETWORK            = os.environ.get("INTERVIEW_NETWORK", "mysql_interview_net")
PREWARM_NETWORK    = os.environ.get("INTERVIEW_PREWARM_NETWORK", "mysql_interview_prewarm_net")
STATE_FILE         = Path(os.environ.get("STATE_FILE", "/state/level.txt"))
RESULTS_FILE       = Path(os.environ.get("RESULTS_FILE", "/state/results.json"))
STARTED_FILE       = Path(os.environ.get("STARTED_FILE", "/state/started_at.txt"))
INPUT_FILE         = Path(os.environ.get("INPUT_FILE", "/state/input_events.json"))
LOCK_FILE          = Path(os.environ.get("LOCK_FILE", "/state/input_lock.json"))
DURATION_SECONDS   = int(os.environ.get("DURATION_SECONDS", "10800"))
HISTORY_VOLUME     = os.environ.get("HISTORY_VOLUME", "mysql-interview-history")
MEM_LIMIT          = os.environ.get("EXERCISE_MEM_LIMIT", "1g")
HISTORY_DIR        = Path(os.environ.get("HISTORY_DIR", "/state/history"))
EXERCISES_DIR      = Path("/exercises")
LABEL              = "mysql-interview"
RUN_FILE           = Path(os.environ.get("RUN_FILE", "/state/run.json"))
ARCHIVE_DIR        = Path(os.environ.get("ARCHIVE_DIR", "/state/archive"))
# Shared with nginx (see docker-compose.yml); every request that did not come
# through nginx is refused.
CONTROLLER_SECRET  = os.environ.get("CONTROLLER_SECRET", "interview-lab-local-only")
CONTROLLER_HEADER  = "X-Controller-Key"
# A grader is a handful of mysql queries and is done in seconds; CHECK_TIMEOUT
# is the hard stop for one that is not. A candidate query with a missing join
# condition is a 300k x 331k x 443k row cross join, and check.sh runs the
# candidate's SQL as written — without a stop the exec never returns, the
# request holds the level lock for good and the interview is over for everyone.
# CHECK_SETTLE is how long a failing check is re-sampled before the failure is
# final. Several checks read state that is still moving when Send is pressed —
# an IO thread in Connecting, a relay log draining, a connection pool
# rebuilding — and one sample taken a second too early fails a candidate who
# fixed the problem. The per-sample stop is kept shorter than the window.
CHECK_TIMEOUT      = int(os.environ.get("CHECK_TIMEOUT", "20"))
CHECK_SETTLE       = int(os.environ.get("CHECK_SETTLE", "30"))
CHECK_INTERVAL     = int(os.environ.get("CHECK_INTERVAL", "4"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("controller")

app = Flask(__name__)
client = docker.from_env()
_lock = threading.Lock()
_input_lock = threading.Lock()
_terminal_lock = threading.Lock()
_net_lock = threading.Lock()
# One prewarm spawn at a time. Each one starts by deleting whatever prewarm set
# exists, so two running together interleave into a set of mixed levels.
_prewarm_lock = threading.Lock()


@app.before_request
def require_proxy_secret():
    """Refuse anything that did not come through nginx.

    All authentication lives in nginx (site-wide basic auth, the
    interviewer-only locations), and nginx stamps every request it forwards
    with a shared secret. The controller sits on a network the candidate
    cannot reach, but the candidate has a root shell one hop away from it, so
    a missing or wrong secret is treated as hostile whatever route was asked
    for: the interviewer's pass/fail view and /reset are the obvious prizes,
    and there is no legitimate client other than nginx.
    """
    given = request.headers.get(CONTROLLER_HEADER, "")
    if not hmac.compare_digest(given.encode("utf-8"),
                               CONTROLLER_SECRET.encode("utf-8")):
        return jsonify({"error": "forbidden"}), 403


# -------- state files --------
def atomic_write(path: Path, text: str) -> None:
    """Write `text` to `path` so a reader sees the old file or the new one,
    never a truncated one.

    Every state file here is tiny and rewritten whole, and write_text()
    truncates before it writes. A crash or a full disk inside that window
    leaves an empty file, and an empty results.json or level.txt reads back
    as "no results" and "level 1" — the evidence gone with no error anywhere.
    Writing beside the target and renaming over it makes the switch atomic;
    the fsync first is so the rename cannot land before the bytes do.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# -------- level state --------
def get_level() -> int:
    if not STATE_FILE.exists():
        return 1
    try:
        return max(1, int(STATE_FILE.read_text().strip() or "1"))
    except ValueError:
        return 1


def set_level(n: int) -> None:
    atomic_write(STATE_FILE, str(n))


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
    atomic_write(STARTED_FILE, str(ts))
    return ts


# -------- run identity --------
# A run is one candidate, from Start to reset. Everything written during it —
# transcripts on the history volume, the archived state after reset — is filed
# under the run id, so two candidates can never share a file.
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def _new_run_id() -> str:
    """Time-ordered so the archive lists chronologically, with a random tail so
    two runs minted in the same second can never share a directory."""
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(3)


def load_run() -> dict:
    try:
        return json.loads(RUN_FILE.read_text())
    except (OSError, ValueError):
        return {}


def get_run_id() -> str | None:
    """The current run's id, or None when this state predates run ids.

    The id names a directory on the history volume, so anything that does not
    look like a plain token is ignored rather than joined into a path."""
    rid = load_run().get("run_id")
    if isinstance(rid, str) and RUN_ID_RE.match(rid):
        return rid
    return None


def ensure_run_id() -> str:
    """Return the run id, minting one if this run has none yet."""
    rid = get_run_id()
    if rid is not None:
        return rid
    rid = _new_run_id()
    atomic_write(RUN_FILE, json.dumps({"run_id": rid, "created": _now()},
                                      indent=2, sort_keys=True))
    return rid


def archive_state() -> None:
    """Move this run's state files under ARCHIVE_DIR/<run_id>/ instead of
    deleting them.

    Reset is one click on the interviewer page, and it used to unlink the
    scoreboard, the paste log and the acknowledgement outright — irrecoverable
    the moment a finger slipped. Moving them costs nothing and keeps the
    evidence. Transcripts are left alone: they live under the run's own
    directory on the history volume, and the next run writes somewhere else.
    """
    dest = ARCHIVE_DIR / (get_run_id() or f"no-run-id-{_new_run_id()}")
    # Held so a save or a burst report landing mid-reset cannot recreate a
    # file we have just moved and leave the new run starting with old data.
    with _input_lock, _file_lock:
        present = [f for f in (STATE_FILE, RESULTS_FILE, STARTED_FILE, INPUT_FILE, LOCK_FILE,
                               FILE_EVENTS, ACK_FILE, RUN_FILE) if f.exists()]
        if not present:
            return
        dest.mkdir(parents=True, exist_ok=True)
        for f in present:
            shutil.move(str(f), str(dest / f.name))
    log.info("archived %d state files to %s", len(present), dest)


def load_input_events() -> dict:
    if not INPUT_FILE.exists():
        return {}
    try:
        return json.loads(INPUT_FILE.read_text())
    except (json.JSONDecodeError, ValueError):
        return {}


def load_input_lock() -> dict:
    try:
        return json.loads(LOCK_FILE.read_text())
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        # A damaged lock record must never silently reopen a candidate shell.
        return {"reason": "lock state could not be read"}


def set_terminal_access(enabled: bool) -> list[str]:
    """Stop/start ttyd without stopping MySQL or the exercise container."""
    errors = []
    for node in read_nodes(get_level()):
        try:
            c = client.containers.get(container_name(node))
            rc, out = c.exec_run(["systemctl", "start" if enabled else "stop", "ttyd.service"])
            if rc:
                errors.append(f"{node}: {(out or b'').decode('utf-8', 'replace')[:120]}")
        except docker.errors.NotFound:
            continue
        except Exception as e:
            errors.append(f"{node}: {e}")
    if errors:
        log.error("ttyd %s failed: %s", "start" if enabled else "stop", errors)
    return errors


def locked_response():
    return jsonify({"error": "Session locked after rejected input. The interviewer has been notified.",
                    "locked": True, "lock": load_input_lock()}), 423


def record_input_event(level: int, kind: str, detail: str, run_id: str | None = None) -> bool:
    """Log one suspicious-input event for a level.

    `kind` is "rejected" (input no hand produces — inserted in one piece, a
    machine burst or a machine-steady beat — dropped by the terminal guard
    or the Files editor, see static/cadence.js), "automation" (webdriver/CDP
    signals at page load), "respawn" (a node's container came back), or
    "burst" (older runs, before bursts were rejected). Evidence for a human
    to weigh, not a verdict: dictation also inserts whole words.
    """
    with _input_lock:
        # A delayed beacon from an old tab must not lock the next candidate.
        if (run_id is not None and run_id != get_run_id()) or get_started_at() is None:
            return False
        data = load_input_events()
        entry = data.setdefault(str(level), {"count": 0, "events": []})
        entry["count"] += 1
        entry["events"].append({"at": _now(), "kind": kind, "detail": detail[:200]})
        entry["events"] = entry["events"][-50:]
        if kind == "rejected" and not load_input_lock():
            atomic_write(LOCK_FILE, json.dumps({"at": _now(), "level": level,
                                               "reason": detail[:200], "run_id": run_id},
                                              indent=2, sort_keys=True))
        atomic_write(INPUT_FILE, json.dumps(data, indent=2, sort_keys=True))
        return True


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_results() -> dict:
    """The scoreboard. An unreadable file is an error, not an empty
    scoreboard: writes are atomic, so a results.json that does not parse
    means something is genuinely wrong, and a dashboard that quietly showed
    "no results" would hide exactly that."""
    if not RESULTS_FILE.exists():
        return {}
    try:
        return json.loads(RESULTS_FILE.read_text())
    except ValueError as e:
        raise RuntimeError(f"{RESULTS_FILE} is not valid JSON: {e}") from e


def save_results(results: dict) -> None:
    atomic_write(RESULTS_FILE, json.dumps(results, indent=2, sort_keys=True))


def record_start(level: int) -> None:
    r = load_results()
    key = str(level)
    if key not in r:
        r[key] = {"started": _now(), "attempts": 0, "passed": False}
        save_results(r)


def record_attempt(level: int, passed: bool, output: str = "") -> None:
    r = load_results()
    key = str(level)
    entry = r.setdefault(key, {"started": _now(), "attempts": 0, "passed": False})
    entry["attempts"] = entry.get("attempts", 0) + 1
    entry["last_attempt"] = _now()
    # What check.sh printed: the reason the grade came out the way it did.
    # Without it the dashboard shows FAILED and nothing else, and the
    # interviewer is left to reconstruct why from the transcript.
    entry["output"] = output[:4000]
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
    """One line per node name in exercises/NN-*/nodes.txt; default ['node1']."""
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


def _recreate_internal(net) -> None:
    """Replace `net` with an internal network of the same name, keeping
    whatever was attached to it attached.

    `networks.create` never reconfigures an existing network, so on a host
    that predates the internal flag the network stays exactly as it was
    created: with a route to the internet. The only way to change that is to
    remove and recreate it, and nginx (and possibly live exercise nodes) sit
    on it, so they are detached first and reattached, with their aliases,
    afterwards. If the network cannot be removed everything is put back and
    the condition is logged; a spawn should not die over it.
    """
    name = net.name
    attached = []
    for cid in list((net.attrs.get("Containers") or {}).keys()):
        try:
            c = client.containers.get(cid)
        except docker.errors.NotFound:
            c = None
        if c is not None:
            ep = ((c.attrs.get("NetworkSettings") or {}).get("Networks") or {}).get(name) or {}
            # Docker adds the short id back on its own; the rest are the
            # aliases compose or promote_prewarm asked for.
            aliases = [a for a in (ep.get("Aliases") or []) if a != c.short_id]
            attached.append((c, aliases))
        try:
            net.disconnect(cid, force=True)
        except docker.errors.APIError as e:
            log.warning("could not detach %s from %s: %s", cid[:12], name, e)

    try:
        net.remove()
    except docker.errors.APIError as e:
        log.warning("network %s is not internal and could not be replaced (%s); "
                    "containers on it can still reach the internet", name, e)
        for c, aliases in attached:
            try:
                net.connect(c, aliases=aliases or None)
            except docker.errors.APIError as e2:
                log.warning("could not reattach %s to %s: %s", c.name, name, e2)
        return

    new = client.networks.create(name, driver="bridge", internal=True)
    for c, aliases in attached:
        try:
            new.connect(c, aliases=aliases or None)
        except docker.errors.APIError as e:
            log.warning("could not reattach %s to %s: %s", c.name, name, e)
            continue
        # Docker binds a container's published ports to its first non-internal
        # endpoint. If that endpoint was on the network just removed — nginx
        # started while it was still a plain bridge — the bindings went with
        # it, and only a restart brings them back, now on the controller
        # network where they belong. A one-off on hosts that predate the
        # internal flag; anything without published ports is left running.
        if _publishes_ports(c):
            log.warning("restarting %s so its published ports rebind after "
                        "%s was recreated", c.name, name)
            try:
                c.restart(timeout=5)
            except docker.errors.APIError as e:
                log.warning("restart of %s failed: %s", c.name, e)
    log.info("recreated network %s as internal (%d containers reattached)",
             name, len(attached))


def _publishes_ports(c) -> bool:
    ports = (c.attrs.get("NetworkSettings") or {}).get("Ports") or {}
    return any(ports.values())


def ensure_networks() -> None:
    """Both exercise networks exist and are internal.

    Nothing in an exercise needs the internet at runtime — packages come
    from a repository staged into the image at build time — and a
    candidate with a root shell and a route out has a straight line to any
    AI service they like. An internal network has no gateway, so the shell
    simply cannot reach anything that is not another lab container.
    """
    with _net_lock:
        for n in (NETWORK, PREWARM_NETWORK):
            try:
                net = client.networks.get(n)
            except docker.errors.NotFound:
                client.networks.create(n, driver="bridge", internal=True)
                continue
            if not net.attrs.get("Internal", False):
                _recreate_internal(net)


def _spawn(level: int, role: str, only: list[str] | None = None) -> str | None:
    """Spawn containers for `level` with `role` in ('current', 'prewarm').

    Without `only` the whole node set is started and whatever the role had is
    removed first. With `only`, just those nodes are started beside the ones
    already running, exactly as the full spawn would have started them (same
    image, name, hostname, env, peers, limits): index() uses it to bring back
    a lone node that died mid-question without touching the live ones.
    Returns None on success, error message otherwise."""
    ensure_networks()
    if role == "current":
        net, name_fn, prefix = NETWORK, container_name, CURRENT_PREFIX
    else:
        net, name_fn, prefix = PREWARM_NETWORK, prewarm_name, PREWARM_PREFIX
    if only is None:
        _stop_by_prefix(prefix)
    img = image_name(level)
    try:
        client.images.get(img)
    except docker.errors.ImageNotFound:
        return f"Image {img} is not built. Run ./build.sh first."

    nodes = read_nodes(level)
    # Transcripts are filed per run so the next candidate never appends to
    # this one's files (`script -a` on a fixed name did exactly that). A run
    # that predates run ids keeps the flat layout the dashboard falls back to.
    run_id = get_run_id()
    histdir = (f"/var/log/history/{run_id}/level-{level}" if run_id
               else f"/var/log/history/level-{level}")
    for node in nodes:
        if only is not None and node not in only:
            continue
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
                # Cap each node's memory. Candidates have root inside these
                # containers and can set any memory option — without a cap, mysqld
                # chases the host's real memory and takes down nginx, the
                # controller and sshd with it. With the cap the allocation
                # fails inside the cgroup, mysqld exits with the clean error
                # the question intends, and the host never notices.
                mem_limit=MEM_LIMIT,
                memswap_limit=MEM_LIMIT,
                # Fork-bomb stop; mysqld, a question's client pool and systemd use a few hundred.
                pids_limit=2048,
                tmpfs={"/run": "", "/run/lock": "", "/tmp": ""},
                environment={
                    "NODE_NAME": node,
                    "NODE_INDEX": str(nodes.index(node)),
                    "NODE_PEERS": ",".join(nodes),
                    "LEVEL": str(level),
                    "HISTDIR": histdir,
                },
                volumes={
                    HISTORY_VOLUME: {"bind": "/var/log/history", "mode": "rw"},
                    "/sys/fs/cgroup": {"bind": "/sys/fs/cgroup", "mode": "rw"},
                },
                labels={LABEL: "true", "level": str(level), "node": node, "role": role},
            )
        except docker.errors.APIError as e:
            # A set that is half up is no use, so the full spawn clears it. A
            # respawn that failed leaves the live nodes alone: killing them
            # over one missing node is the outage this path exists to avoid.
            if only is None:
                _stop_by_prefix(prefix)
            return f"docker run failed for {name}: {e}"
    return None


def start_exercise(level: int) -> str | None:
    return _spawn(level, "current")


def missing_nodes(level: int) -> list[str]:
    """Nodes of `level` whose current container does not exist."""
    missing = []
    for node in read_nodes(level):
        try:
            client.containers.get(container_name(node))
        except docker.errors.NotFound:
            missing.append(node)
    return missing


def prewarm_ready(level: int) -> bool:
    """A complete prewarm set for `level`, by name and level label, is up."""
    for node in read_nodes(level):
        try:
            c = client.containers.get(prewarm_name(node))
        except docker.errors.NotFound:
            return False
        if c.labels.get("level") != str(level):
            return False
    return True


def prewarm_next(level: int) -> None:
    """Best-effort prewarm of `level+1` in a background thread."""
    next_level = level + 1
    if next_level > MAX_LEVEL or not image_exists(next_level):
        return
    try:
        with _prewarm_lock:
            # A single-node level whose node died is respawned through the
            # full spawn and lands here again; the next level is already
            # warm, and replacing it would only make the next Send wait for
            # a boot.
            if prewarm_ready(next_level):
                return
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
        except docker.errors.NotFound:
            return False
        # The names say nothing about the question: a set left by an earlier
        # prewarm has the same ones, and promoting it would serve the wrong
        # exercise.
        if c.labels.get("level") != str(level):
            log.warning("prewarm %s is for level %s, not %d; spawning fresh",
                        c.name, c.labels.get("level"), level)
            return False
        promoted.append((node, c))

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


class CheckUnavailable(Exception):
    """The grader could not be started at all, as opposed to running and
    failing. Raised for a missing container or a missing script: neither says
    anything about the candidate's work, and recording them as a failed
    attempt would cost the question for a lab fault. A grader that starts and
    then hangs is a different matter — see _exec_with_deadline."""


# Runs the grader under coreutils `timeout` so an overrun kills the grader's
# whole process group, which is what actually stops a runaway query. The
# script travels as a positional parameter so no quoting can go wrong, and a
# container without `timeout` still runs the check, just without the stop.
_TIMEOUT_WRAPPER = ('if command -v timeout >/dev/null 2>&1; then '
                    'exec timeout -k 5 "$1" /bin/bash -c "$2"; fi; '
                    'exec /bin/bash -c "$2"')


def _exec_with_deadline(c, script: str, timeout: int) -> tuple[int | None, str]:
    """Run `script` in container `c`. Returns (exit code, output), or
    (None, reason) when the check did not finish.

    Two layers, because either alone leaves a hole. `timeout` inside the
    container is what stops the grader; the exec then returns normally with
    124 (or 137 after the follow-up KILL). The thread join is for when the
    exec itself never comes back: the SDK reads the exec socket with no
    timeout of its own, so a Docker hiccup would otherwise park this request,
    and the lock it holds, for good. A thread left behind by the join ends on
    its own and is never waited on. Anything the exec raises is a check that
    did not finish, not an outage: by this point the container was there and
    the grader was started, and the runaway is almost always the candidate's
    own query, so the attempt is recorded as failed with the reason rather
    than turned into a 500 that leaves the interview stuck.
    """
    result: dict = {}

    def run():
        try:
            result["done"] = c.exec_run(
                ["/bin/bash", "-c", _TIMEOUT_WRAPPER, "check", str(timeout), script],
                demux=False)
        except Exception as e:
            result["exc"] = e

    t = threading.Thread(target=run, daemon=True)
    t.start()
    t.join(timeout + 15)
    if t.is_alive():
        return None, f"the check did not return within {timeout + 15}s"
    if "exc" in result:
        return None, f"the check did not complete: {result['exc']}"
    rc, out = result["done"]
    text = (out.decode("utf-8", errors="replace") if out else "").strip()
    if rc in (124, 137):
        reason = f"the check did not finish within {timeout}s and was killed"
        return None, f"{text}\n{reason}" if text else reason
    return rc, text


def run_check(level: int) -> tuple[bool, str]:
    """Run the level's check.sh inside the first node, without it ever
    touching disk. Returns (passed, output); raises CheckUnavailable when the
    check could not be started.

    The check is sampled every CHECK_INTERVAL seconds for up to CHECK_SETTLE
    seconds and passes on two consecutive passing samples — two, so a flapping
    state that happens to be green for one instant is not rewarded. A correct
    answer therefore costs one interval; a wrong one costs the whole window,
    which is the price of not failing people for pressing Send a second early.

    The grader is deliberately NOT baked into the exercise image. The
    candidate has passwordless sudo (they need it to drive systemctl and edit
    my.cnf), so any grader sitting on disk is readable with `sudo cat` — which
    would hand them the pass criteria and, for some questions, the answer.

    The script source is handed straight to `bash -c`, so nothing is written
    into the container at all. (Copying it in is not an option: /tmp, /run and
    /run/lock are tmpfs mounts, and Docker's put_archive writes into the image
    layer underneath the mount, where exec cannot see it.)
    """
    d = level_dir(level)
    if not d:
        raise CheckUnavailable(f"no exercise directory for level {level}")
    script = d / "check.sh"
    if not script.exists():
        raise CheckUnavailable(f"{script} is missing")

    first = first_node_container(level)
    try:
        c = client.containers.get(first)
    except docker.errors.NotFound:
        raise CheckUnavailable(f"exercise container {first} is not running") from None
    except (docker.errors.DockerException, OSError) as e:
        raise CheckUnavailable(f"could not reach Docker: {e}") from e
    try:
        source = script.read_text()
    except OSError as e:
        raise CheckUnavailable(f"could not read {script}: {e}") from e

    t0 = time.monotonic()
    samples = streak = 0
    while True:
        samples += 1
        rc, text = _exec_with_deadline(c, source, CHECK_TIMEOUT)
        elapsed = int(time.monotonic() - t0)
        if rc is None:
            # A grader that cannot finish is not a state that will settle,
            # and running it again would only stall the interview further.
            return False, f"[grader: sample {samples} did not finish]\n{text}"
        streak = streak + 1 if rc == 0 else 0
        if streak >= 2:
            return True, (f"[grader: passed on samples {samples - 1} and {samples}, "
                          f"{elapsed}s after Send]\n{text}")
        # The window closes only on a failing sample: a first pass right at
        # the end still gets its confirming sample, so the whole thing runs
        # at most one interval past CHECK_SETTLE.
        if streak == 0 and elapsed >= CHECK_SETTLE:
            return False, (f"[grader: no two consecutive passes in {samples} "
                           f"samples over {elapsed}s]\n{text}")
        time.sleep(CHECK_INTERVAL)


# -------- routes --------
@app.route("/")
def index():
    level = get_level()
    if level > MAX_LEVEL or not image_exists(level):
        return render_template("done.html", max_level=MAX_LEVEL)

    # Nothing has started yet: show the briefing and only the briefing. No
    # exercise is spawned and no clock runs, so a candidate who opens the link
    # early is not quietly burning their time.
    if get_started_at() is None:
        return render_template("start.html", max_level=MAX_LEVEL,
                               duration_seconds=DURATION_SECONDS)

    if load_input_lock():
        return render_template("locked.html")

    # Lazy-start what is not running. Every node of the level is probed, not
    # just node1: a lone node that died (`reboot -f`, PID 1 taken by the OOM
    # killer; the containers are auto_remove, so it is simply gone) is
    # respawned on its own and the live ones are left alone. The full spawn
    # clears the set first and a `docker run` into a name that still exists
    # fails, so one dead node used to cost the candidate every node. The
    # respawned node boots into its start-of-question state — setup.sh runs
    # again, with a fresh server UUID and an empty GTID set — so on a
    # multi-node question replication to or from it is gone and the candidate
    # has to wire it back in; node1's setup re-drives repl-bootstrap, which
    # may re-point the other replicas at it. A question that breaks mysqld
    # inside a node leaves the container up, so it never gets here. The event is logged
    # for the interviewer, who decides what it is worth.
    if missing_nodes(level):
        with _lock:
            # Re-read: a Send may have moved the level while waiting for the
            # lock, and the old level's node list would spawn its nodes on
            # top of the new one's.
            level = get_level()
            if level > MAX_LEVEL or not image_exists(level):
                return render_template("done.html", max_level=MAX_LEVEL)
            missing = missing_nodes(level)
            if missing:
                names = ", ".join(missing)
                whole = len(missing) == len(read_nodes(level))
                err = start_exercise(level) if whole else _spawn(level, "current", only=missing)
                if err and whole:
                    return render_template("error.html", message=err), 500
                if err:
                    # The page still renders: the live nodes work, the dead
                    # one's frame keeps asking, and the next ask retries.
                    log.error("respawn of %s for level %d failed: %s", names, level, err)
                    record_input_event(level, "respawn",
                                       f"{names}: container gone, respawn failed: {err}")
                else:
                    record_input_event(level, "respawn",
                                       f"{names}: container gone, respawned from the question's "
                                       "initial state" + ("" if whole else "; other nodes untouched"))
                if whole:
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
        run_id=get_run_id(),
        suggested_files=suggested_files(level),
    )


@app.route("/start", methods=["POST"])
def start():
    """Begin the interview: record the acknowledgement, then start the clock.

    The clock is set last and only if the first exercise actually came up, so a
    failed start never costs the candidate time."""
    data = request.get_json(silent=True, force=True) or {}
    if not data.get("ack"):
        return jsonify({"error": "Please tick the box to confirm you have read "
                                 "the rules."}), 400
    with _lock:
        if get_started_at() is not None:
            return jsonify({"ok": True, "already": True})
        level = get_level()
        # Minted before the first spawn so the containers know which run's
        # history directory to write into.
        ensure_run_id()
        err = start_exercise(level)
        if err:
            return jsonify({"error": err}), 500
        threading.Thread(target=prewarm_next, args=(level,), daemon=True).start()
        record_ack(request.headers.get("User-Agent", ""))
        ensure_started_at()
    return jsonify({"ok": True})


@app.route("/check", methods=["POST"])
def check():
    """Run the level's check, record pass/fail, and advance.
    The candidate sees no pass/fail signal — the interviewer dashboard does.

    The only thing that stops the advance is the check not running at all;
    a failed grade still moves on, as it always has."""
    data = request.get_json(silent=True, force=True) or {}
    with _lock:
        if load_input_lock():
            return locked_response()
        level = get_level()
        if level > MAX_LEVEL:
            return jsonify(submitted=True, done=True)
        # A page that knows which question it is showing says so, and a Send
        # for any other question is refused. Two clicks in quick succession,
        # or a stale tab, would otherwise grade the next level's still-booting
        # container, record a failure the candidate never earned and skip a
        # question. A page that sends no level is graded as before.
        if data.get("level") is not None:
            try:
                wanted = int(data["level"])
            except (TypeError, ValueError):
                return jsonify(submitted=False, error="level must be a number"), 400
            if wanted != level:
                return jsonify(submitted=False, current=level,
                               error=f"question {wanted} is not the one in progress"), 409
        try:
            passed, output = run_check(level)
        except CheckUnavailable as e:
            # Nothing is known about the candidate's work, so nothing is
            # recorded and the level stays put. Reloading the page brings
            # the container back and they can send again.
            log.error("check for level %d did not run: %s", level, e)
            return jsonify(submitted=False,
                           error=f"The check could not run ({e}). Nothing was "
                                 "recorded; reload the page and send again."), 503
        if load_input_lock():
            return locked_response()
        record_attempt(level, passed, output)
        new_level = level + 1
        set_level(new_level)
        # The attempt is recorded and the level has moved, so from here the
        # answer is "submitted" whatever Docker does. An error escaping now (a
        # docker-py read timeout is not an APIError) used to be a 500 telling
        # the candidate nothing was recorded, and their retry got a 409.
        # Reloading / lazy-starts whatever did not come up.
        done = new_level > MAX_LEVEL
        try:
            if not done and not image_exists(new_level):
                done = True
            if done:
                stop_exercise()
            else:
                if not promote_prewarm(new_level):
                    err = start_exercise(new_level)
                    if err:
                        log.error("level %d did not start after Send: %s", new_level, err)
                threading.Thread(target=prewarm_next, args=(new_level,), daemon=True).start()
        except Exception:
            log.exception("bringing up level %d after Send failed", new_level)
            # index() probes names, not levels, so the previous level's
            # containers or a half-promoted set would pass for this level.
            # Clearing them makes the reload spawn it whole.
            if not done:
                try:
                    stop_exercise()
                except Exception:
                    log.exception("could not clear containers after the failed start")
        return jsonify(submitted=True, done=done)


@app.route("/reset", methods=["POST"])
def reset():
    with _lock:
        # Archived, not deleted: see archive_state. The next Start mints a
        # new run id, and with it a fresh history directory.
        archive_state()
        set_level(1)
        stop_exercise()
        # Deliberately not spawning here. The next candidate gets the briefing
        # page, and pressing Start is what spawns level 1 and begins the clock —
        # one action, so the two can never drift apart. It also means nothing is
        # running between candidates.
    return redirect(url_for("index"))


@app.route("/input-event", methods=["POST"])
def input_event():
    """Terminal or page reports suspicious input (burst typing, automation)."""
    data = request.get_json(silent=True, force=True) or {}
    try:
        level = int(data.get("level", 0))
    except (TypeError, ValueError):
        return ("", 204)
    kind = str(data.get("kind", "burst"))[:32]
    detail = str(data.get("detail", ""))[:200]
    if 0 < level <= MAX_LEVEL and kind in ("burst", "automation", "rejected"):
        with _terminal_lock:
            was_locked = bool(load_input_lock())
            try:
                accepted = record_input_event(level, kind, detail, str(data.get("run_id", "")))
            finally:
                # If the event log write fails after the lock write, existing
                # ttyd sockets still have to be closed.
                if kind == "rejected" and not was_locked and load_input_lock():
                    set_terminal_access(False)
        if accepted:
            return jsonify({"locked": bool(load_input_lock()), "lock": load_input_lock()})
    return ("", 204)


@app.route("/lock-state")
def lock_state():
    lock = load_input_lock()
    return jsonify({"locked": bool(lock), "lock": lock})


@app.route("/term-auth")
def term_auth():
    return ("", 403 if load_input_lock() else 204)


@app.route("/unlock", methods=["POST"])
def unlock():
    with _terminal_lock:
        if not load_input_lock():
            return jsonify({"locked": False})
        errors = set_terminal_access(True)
        if errors:
            return jsonify({"error": "Could not restart terminals", "details": errors}), 503
        with _input_lock:
            LOCK_FILE.unlink(missing_ok=True)
    return jsonify({"locked": False})


@app.route("/healthz")
def healthz():
    return "ok"


# -------- interviewer view --------
_SCRIPT_BANNER_RE = re.compile(rb"^Script (started|done).*$\r?\n?", re.MULTILINE)


def _clean_typescript(data: bytes) -> str:
    """Replay the typescript through a virtual VT100 so backspaces, cursor
    moves, and in-place line redraws (mysql client readline editing) resolve to
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


# Cleaned text per transcript file. A finished level's transcript never
# changes, yet every dashboard load and every editor save replayed them all
# through pyte. Keyed by path and checked against size and mtime, so only a
# file that has grown is replayed, and a growing transcript replaces its own
# entry rather than pushing the finished ones out.
_CLEAN_CACHE: OrderedDict = OrderedDict()
_CLEAN_CACHE_MAX = 64
_clean_cache_lock = threading.Lock()


def _clean_file(f: Path, st) -> str:
    """_clean_typescript of `f`, from the cache while `st` still matches.
    `st` is taken before the read, so bytes landing in between make the entry
    look older than it is and it is replayed again; it is never served stale.
    Raises OSError when the file cannot be read."""
    key, stamp = str(f), (st.st_size, st.st_mtime_ns)
    with _clean_cache_lock:
        hit = _CLEAN_CACHE.get(key)
        if hit is not None and hit[0] == stamp:
            _CLEAN_CACHE.move_to_end(key)
            return hit[1]
    text = _clean_typescript(f.read_bytes())
    with _clean_cache_lock:
        _CLEAN_CACHE[key] = (stamp, text)
        _CLEAN_CACHE.move_to_end(key)
        while len(_CLEAN_CACHE) > _CLEAN_CACHE_MAX:
            _CLEAN_CACHE.popitem(last=False)
    return text


def _timing_stats(level_dir: Path, node: str) -> dict | None:
    """Summarise typing rhythm from `script -t` timing files.

    Format is one `<delay> <bytes>` line per write, delay being seconds since
    the previous one. With `script -f` every keystroke echoes, so the delays
    approximate typing rhythm: a long gap means nobody was typing.

    Only idle gaps are meaningful here. `script` records the timing of
    everything the terminal WRITES, and command output is inherently bursty —
    one `cat` produces hundreds of writes microseconds apart — so a "fast
    typing" metric derived from this file would flag everyone who ran a
    command. Machine-speed input detection lives in the browser instead
    (static/terminal-guard.js), where keydown events can be counted directly.

    A long idle gap followed by a correct, confident command is still the
    pattern worth looking for, and it survives a phone camera — which no
    screenshot measure does.
    """
    IDLE = 60.0
    delays: list[float] = []
    for f in sorted(level_dir.glob(f"{node}-*.timing")):
        try:
            for line in f.read_text(errors="replace").splitlines():
                parts = line.split(None, 1)
                if not parts:
                    continue
                try:
                    delays.append(float(parts[0]))
                except ValueError:
                    continue
        except OSError:
            continue
    if not delays:
        return None
    gaps = [d for d in delays if d >= IDLE]
    return {
        "elapsed_s": int(sum(delays)),
        "idle_s": int(sum(gaps)),
        "gap_count": len(gaps),
        "longest_gap_s": int(max(delays)),
    }


def history_level_dir(level: int) -> Path | None:
    """Where this run's transcripts and preserved files for `level` live.

    Each run writes under its own directory, so one candidate's session can
    never be read as another's — and never matched by the paste classifier as
    "typed in this session" when it was typed by someone else last week. Only
    state that predates run ids (no run.json) falls back to the flat legacy
    layout, so old evidence still renders. A run that has an id never falls
    back: an absent directory means nothing has happened on that level yet,
    not that the previous candidate's files should be shown instead.
    """
    run_id = get_run_id()
    if run_id:
        d = HISTORY_DIR / run_id / f"level-{level}"
        return d if d.is_dir() else None
    for d in (HISTORY_DIR / f"level-{level}", HISTORY_DIR / f"level-{level:02d}"):
        if d.is_dir():
            return d
    return None


def _read_artifacts(level: int) -> list[dict]:
    """Files a candidate submitted that are meant to be read, not graded.

    check.sh copies these out before the container is destroyed — the
    written assessment and the SQL the candidate composed. Without this the
    most human-readable evidence in the lab would vanish the instant they
    pressed Send.
    """
    d = history_level_dir(level)
    if d is None:
        return []
    out = []
    for name, label in (("report.md", "Written assessment"),
                        ("answer.sql", "Submitted query")):
        f = d / name
        if f.is_file():
            try:
                text = f.read_text(errors="replace").strip()
            except OSError:
                continue
            if text:
                out.append({"name": name, "label": label, "text": text})
    return out


def _read_sessions(level: int) -> list[dict]:
    """One transcript per node per level. Coalesces the legacy per-PID
    files (`<node>-session-<pid>.typescript`) and the current per-node
    files (`<node>.typescript`) into a single chronological block per node:
    {"node": str, "mtime": iso, "text": str}."""
    hdir = history_level_dir(level)
    if hdir is None:
        return []

    by_node: dict[str, list[tuple[float, str]]] = {}
    for f in hdir.iterdir():
        if not f.is_file() or not f.name.endswith(".typescript"):
            continue
        m = re.match(r"^(?P<node>.+?)(?:-session-\d+)?\.typescript$", f.name)
        node = m.group("node") if m else f.stem
        try:
            st = f.stat()
            text = _clean_file(f, st)
        except OSError:
            continue
        if not text:
            continue
        by_node.setdefault(node, []).append((st.st_mtime, text))

    sessions: list[dict] = []
    for node, chunks in by_node.items():
        chunks.sort(key=lambda t: t[0])
        text = "\n".join(c for _, c in chunks).strip()
        if not text:
            continue
        last = max(t for t, _ in chunks)
        mtime = datetime.fromtimestamp(last, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        sessions.append({"node": node, "mtime": mtime, "text": text,
                         "timing": _timing_stats(hdir, node)})
    sessions.sort(key=lambda s: s["node"])
    return sessions


# -------- candidate file manager --------

# Candidates cannot paste into the terminal, which is deliberate, but it makes
# long literal statements (CHANGE REPLICATION SOURCE ...) an exercise in typing
# rather than in knowing MySQL. The editor gives them a place to compose and
# paste those, at the cost of opening a transfer channel from outside the lab.
#
# We do not try to close that channel — the candidate has passwordless sudo and
# could write any file from the shell anyway. Instead every save is recorded
# with its content and with how the content arrived, so a pasted answer is the
# most visible thing in the session rather than the least.
FILES_HOME      = "/home/candidate"
FILE_MAX_BYTES  = 64 * 1024
FILE_MAX_LIST   = 200
# Flat names only: no slashes at all, so there is nothing to traverse and no
# symlink to aim at. Confinement falls out of the name check.
# Leading dot stays out (no quietly-edited dotfiles); a leading underscore
# is ordinary and allowed.
FILE_NAME_RE    = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$")
FILE_EVENTS     = Path(os.environ.get("FILE_EVENTS_FILE", "/state/file_events.json"))
_file_lock      = threading.Lock()


ACK_FILE = Path(os.environ.get("ACK_FILE", "/state/ack.json"))
# Stored verbatim so that what the candidate agreed to can be quoted back
# later, rather than reconstructed from whatever the page says today.
ACK_TEXT = ("I have read the rules above, and I will not use AI assistance "
            "during this test.")


def load_ack() -> dict:
    try:
        return json.loads(ACK_FILE.read_text())
    except (OSError, ValueError):
        return {}


def record_ack(agent: str = "") -> None:
    atomic_write(ACK_FILE, json.dumps(
        {"at": _now(), "text": ACK_TEXT, "agent": agent[:200]},
        indent=2, sort_keys=True))


def is_human_graded(level: int) -> bool:
    """A `human_graded` marker in the exercise directory means check.sh only
    confirms something was submitted; whether it is any good is for the
    interviewer to read. Such a "pass" is not counted as one."""
    d = level_dir(level)
    return bool(d and (d / "human_graded").exists())


def suggested_files(level: int) -> list[str]:
    """Filenames the question itself names under /home/candidate.

    Q1 wants answer.txt, Q9 answer.sql, Q11 report.md. Reading them out of the
    README means the editor offers the right name instead of leaving the
    candidate to notice the path in the prose and retype it.
    """
    d = level_dir(level)
    if not d or not (d / "README.md").exists():
        return []
    try:
        body = (d / "README.md").read_text()
    except OSError:
        return []
    seen, out = set(), []
    for m in re.findall(r"/home/candidate/([A-Za-z0-9._-]+)", body):
        if m not in seen and FILE_NAME_RE.match(m):
            seen.add(m)
            out.append(m)
    return out




def load_file_events() -> dict:
    try:
        return json.loads(FILE_EVENTS.read_text())
    except (OSError, ValueError):
        return {}


def _classify_paste(level: int, node: str, text: str, session: str) -> str:
    """Where did this pasted text come from?

    Pasting is not cheating by itself — the question text and the candidate's
    own terminal output are both legitimate sources. What matters is text with
    no origin inside the session, because that came from outside the lab.

    `session` is the node's transcript for the level, whitespace-collapsed.
    The caller replays it once per save; once per paste made a save with
    twenty pastes replay every transcript twenty times.
    """
    probe = " ".join(text.split())
    # Short pastes are not worth flagging. `START REPLICA;` typed into a
    # notepad and pasted back is not evidence of anything, and a red banner on
    # it would train the interviewer to ignore the banner that matters. The
    # shortest answer worth transferring in these questions (an index
    # definition, a query) is comfortably above this.
    if len(probe) < 40:
        return "trivial"
    d = level_dir(level)
    if d and (d / "README.md").exists():
        try:
            if probe in " ".join((d / "README.md").read_text().split()):
                return "question"
        except OSError:
            pass
    if probe in session:
        return "session"
    return "external"


def record_file_event(level: int, node: str, name: str, content: str,
                      telemetry: dict) -> dict:
    """Log one save: what was written, and how it got there.

    Returns the stored entry so the caller can surface the classification."""
    raw_pastes = (telemetry.get("pastes") or [])[:20]
    session = ""
    if raw_pastes:
        session = next((" ".join(s.get("text", "").split())
                        for s in _read_sessions(level) if s.get("node") == node), "")
    pastes = []
    for p in raw_pastes:
        ptext = str(p.get("text", ""))[:4000]
        pastes.append({
            "bytes": int(p.get("bytes", len(ptext)) or 0),
            "origin": _classify_paste(level, node, ptext, session),
        })
    typed  = int(telemetry.get("typed", 0) or 0)
    pasted = sum(p["bytes"] for p in pastes)
    entry = {
        "at": _now(),
        "node": node,
        "name": name,
        "bytes": len(content.encode("utf-8")),
        "typed": typed,
        "pasted": pasted,
        "pastes": pastes,
        "external": any(p["origin"] == "external" for p in pastes),
        "edit_seconds": int(telemetry.get("seconds", 0) or 0),
        "content": content[:20000],
    }
    with _file_lock:
        data = load_file_events()
        bucket = data.setdefault(str(level), {"count": 0, "saves": []})
        bucket["count"] += 1
        bucket["saves"].append(entry)
        bucket["saves"] = bucket["saves"][-60:]
        atomic_write(FILE_EVENTS, json.dumps(data, indent=2, sort_keys=True))
    return entry


def _node_container(level: int, node: str):
    """Resolve a candidate-supplied node name to its running container."""
    if node not in read_nodes(level):
        return None, "unknown node"
    try:
        return client.containers.get(container_name(node)), None
    except docker.errors.NotFound:
        return None, "that node is not running"


@app.route("/files")
def files_list():
    level = get_level()
    node = request.args.get("node", "")
    c, err = _node_container(level, node)
    if err:
        return jsonify({"error": err, "files": []}), 400
    rc, out = c.exec_run(["/bin/bash", "-c",
        f"cd {FILES_HOME} 2>/dev/null && find . -maxdepth 1 -type f "
        f"-printf '%f\\t%s\\t%T@\\n' 2>/dev/null | sort"])
    files = []
    if rc == 0 and out:
        for line in out.decode("utf-8", "replace").splitlines()[:FILE_MAX_LIST]:
            parts = line.split("\t")
            if len(parts) != 3 or not FILE_NAME_RE.match(parts[0]):
                continue
            try:
                # Too large to edit here, so not offered. Q2's 36 MB dump now
                # lives in /home/candidate, and opening it would show binary
                # garbage that a single Save would write back over the dump.
                if int(parts[1]) > FILE_MAX_BYTES:
                    continue
                files.append({"name": parts[0], "size": int(parts[1]),
                              "mtime": float(parts[2])})
            except ValueError:
                continue
    return jsonify({"node": node, "files": files})


@app.route("/file")
def file_read():
    level = get_level()
    node = request.args.get("node", "")
    name = request.args.get("name", "")
    if not FILE_NAME_RE.match(name):
        return jsonify({"error": "bad file name"}), 400
    c, err = _node_container(level, node)
    if err:
        return jsonify({"error": err}), 400
    rc, out = c.exec_run(["/bin/bash", "-c",
        f"f={FILES_HOME}/{name}; "
        f"[ -f \"$f\" ] && [ \"$(stat -L -c %s \"$f\")\" -gt {FILE_MAX_BYTES} ] && exit 3; "
        f"head -c {FILE_MAX_BYTES} \"$f\""])
    if rc == 3:
        return jsonify({"error": "that file is too large to edit here"}), 400
    if rc != 0:
        return jsonify({"name": name, "content": "", "new": True})
    return jsonify({"name": name,
                    "content": out.decode("utf-8", "replace") if out else "",
                    "new": False})


@app.route("/file", methods=["POST"])
def file_save():
    if load_input_lock():
        return locked_response()
    level = get_level()
    data = request.get_json(silent=True, force=True) or {}
    node = str(data.get("node", ""))
    name = str(data.get("name", ""))
    content = data.get("content", "")
    if not isinstance(content, str):
        return jsonify({"error": "content must be text"}), 400
    if not FILE_NAME_RE.match(name):
        return jsonify({"error": "names may use letters, digits, . _ - only "
                                 "(no directories)"}), 400
    raw = content.encode("utf-8")
    if len(raw) > FILE_MAX_BYTES:
        return jsonify({"error": f"file is larger than {FILE_MAX_BYTES // 1024} KB"}), 400
    c, err = _node_container(level, node)
    if err:
        return jsonify({"error": err}), 400

    # base64 through the command string: no quoting to get wrong, and nothing
    # is staged on the host or under a tmpfs mount on the way in.
    b64 = base64.b64encode(raw).decode("ascii")
    path = f"{FILES_HOME}/{name}"
    with _input_lock:
        if load_input_lock():
            return locked_response()
        rc, out = c.exec_run(["/bin/bash", "-c",
            f"[ -f {path} ] && [ \"$(stat -L -c %s {path})\" -gt {FILE_MAX_BYTES} ] && exit 3; "
            f"printf %s {b64} | base64 -d > {path} && "
            f"chown candidate:candidate {path} && chmod 644 {path}"])
    if rc == 3:
        return jsonify({"error": "that file is too large to edit here, and was not changed"}), 400
    if rc != 0:
        return jsonify({"error": (out or b"").decode("utf-8", "replace")[:200]
                                 or "write failed"}), 500

    entry = record_file_event(level, node, name, content,
                              data.get("telemetry") or {})
    return jsonify({"saved": True, "name": name, "node": node,
                    "bytes": entry["bytes"], "external": entry["external"]})


# -------- live terminal view --------
# A persistent VT100 per transcript file. Polling re-feeds only the bytes that
# appeared since the last call, so a 1s poll costs the same at minute 90 as it
# does at minute 1 — re-replaying the whole file each time would not.
_LIVE_CACHE: dict[str, dict] = {}
LIVE_COLS = 140
LIVE_MAX_DELTA = 512 * 1024   # replay at most this much in one poll
LIVE_TAIL      = 256 * 1024   # ...and when skipping ahead, keep this much
LIVE_ROWS = 44


def _live_render(path: Path) -> tuple[str, float]:
    """Return (visible screen, mtime) for one transcript, rendered incrementally."""
    key = str(path)
    try:
        st = path.stat()
    except OSError:
        _LIVE_CACHE.pop(key, None)
        return "", 0.0

    ent = _LIVE_CACHE.get(key)
    # Start over if the file is new, was truncated, or was replaced entirely.
    # (A new run writes under its own directory, so it also gets its own
    # cache entries rather than continuing the previous candidate's screen.)
    if ent is None or ent["inode"] != st.st_ino or st.st_size < ent["offset"]:
        screen = pyte.Screen(LIVE_COLS, LIVE_ROWS)
        ent = {"screen": screen, "stream": pyte.ByteStream(screen),
               "offset": 0, "inode": st.st_ino, "lock": threading.Lock(),
               "text": ""}
        _LIVE_CACHE[key] = ent

    # The dashboard polls every second and a replay can take longer than that.
    # Without this, overlapping polls each read the same unread range (offset is
    # only advanced after the feed) and push the same bytes through one shared
    # pyte stream: duplicated CPU, a corrupted screen, and enough threads parked
    # here to starve the candidate's own requests. A poll that cannot get the
    # lock serves the last render instead; it is at most one second stale.
    if not ent["lock"].acquire(blocking=False):
        return ent["text"], st.st_mtime
    try:
        if st.st_size > ent["offset"]:
            start = ent["offset"]
            # One `cat` of a 40 MB dump would otherwise be replayed in full for a
            # 44-row view. Past a threshold, start again from the tail: the
            # scrollback is lost, which is what the recorded transcript is for.
            if st.st_size - start > LIVE_MAX_DELTA:
                screen = pyte.Screen(LIVE_COLS, LIVE_ROWS)
                ent["screen"], ent["stream"] = screen, pyte.ByteStream(screen)
                start = st.st_size - LIVE_TAIL
            try:
                with path.open("rb") as fh:
                    fh.seek(start)
                    chunk = fh.read()
            except OSError:
                return ent["text"], st.st_mtime
            ent["stream"].feed(_SCRIPT_BANNER_RE.sub(b"", chunk))
            ent["offset"] = st.st_size

        lines = [ln.rstrip() for ln in ent["screen"].display]
        while lines and not lines[-1].strip():
            lines.pop()
        ent["text"] = "\n".join(lines)
        return ent["text"], st.st_mtime
    finally:
        ent["lock"].release()


def _live_nodes(level: int) -> list[dict]:
    """Current screen for every node on this level, most recently active first."""
    d = history_level_dir(level)
    if d is None:
        return []

    newest: dict[str, Path] = {}
    for f in d.iterdir():
        if not f.is_file() or not f.name.endswith(".typescript"):
            continue
        m = re.match(r"^(?P<node>.+?)(?:-session-\d+)?\.typescript$", f.name)
        node = m.group("node") if m else f.stem
        prev = newest.get(node)
        try:
            if prev is None or f.stat().st_mtime > prev.stat().st_mtime:
                newest[node] = f
        except OSError:
            continue

    out = []
    for node, f in newest.items():
        text, mtime = _live_render(f)
        out.append({
            "node": node,
            "text": text,
            "mtime": mtime,
            "ago": max(0, int(time.time() - mtime)) if mtime else None,
        })
    out.sort(key=lambda n: n["mtime"], reverse=True)
    return out


def _outcome_for(level: int, results: dict, current: int) -> tuple[str, int]:
    r = results.get(str(level), {})
    attempts = r.get("attempts", 0)
    if r.get("passed", False):
        return "passed", attempts
    if level < current:
        return "failed", attempts
    if attempts:
        return "attempted", attempts
    return "pending", attempts


@app.route("/interviewer/live")
def interviewer_live():
    """Everything the dashboard needs to update itself, polled once a second.

    Read-only: it never spawns, checks or mutates anything, so a stuck or
    slow poll cannot disturb a running interview."""
    results = load_results()
    current = get_level()

    inputs = load_input_events()
    levels = []
    passed = failed = 0
    for n in range(1, MAX_LEVEL + 1):
        outcome, attempts = _outcome_for(n, results, current)
        human = is_human_graded(n)
        # A human-graded "pass" only means a report was handed in; counting
        # it would overstate the score by a question the grader never judged.
        if outcome == "passed" and not human:
            passed += 1
        elif outcome == "failed":
            failed += 1
        levels.append({"level": n, "outcome": outcome, "attempts": attempts,
                       "is_current": n == current,
                       "human_graded": human,
                       "check_output": (results.get(str(n)) or {}).get("output", ""),
                       "flags": (inputs.get(str(n)) or {}).get("count", 0)})

    started_at = get_started_at()
    if started_at is not None:
        elapsed = int(time.time()) - started_at
        time_used_h = elapsed / 3600
        overrun_s = max(0, elapsed - DURATION_SECONDS)
    else:
        time_used_h = 0.0
        overrun_s = 0

    return jsonify({
        "current": current,
        "max_level": MAX_LEVEL,
        "passed": passed,
        "failed": failed,
        "time_used_h": round(time_used_h, 2),
        "duration_h": round(DURATION_SECONDS / 3600, 2),
        "overrun_s": overrun_s,
        "levels": levels,
        "nodes": _live_nodes(current),
        "files": (load_file_events().get(str(current)) or {}).get("saves", [])[-8:],
        "ack": load_ack(),
        "input_lock": load_input_lock(),
        # Burst-typing and automation flags for the question in progress.
        # These were recorded all along but only reached the page on a full
        # reload, which stopped happening once the dashboard went live.
        "inputs": (inputs.get(str(current)) or {}).get("events", [])[-8:],
        "served": int(time.time()),
    })


@app.route("/interviewer/")
def interviewer():
    results = load_results()
    inputs = load_input_events()
    file_events = load_file_events()
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
            "human_graded": is_human_graded(n),
            "check_output": r.get("output", ""),
            "sessions": _read_sessions(n),
            "artifacts": _read_artifacts(n),
            "inputs": inputs.get(str(n)),
            # Editor saves, shaped as the live feed sends them. The feed only
            # carries the question in progress, so a pasted answer used to
            # drop off the dashboard the moment the candidate moved on.
            "files": (file_events.get(str(n)) or {}).get("saves", []),
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


# Done at boot as well as at spawn time. On a host that predates the internal
# flag the network has to be replaced before nginx attaches to it: Docker binds
# a container's published ports to its first non-internal endpoint, and nginx's
# port must land on the controller network, not on this one. docker-compose.yml
# starts nginx only once /healthz answers, which is after this has run.
try:
    ensure_networks()
except Exception:
    log.exception("could not verify the exercise networks at boot")
