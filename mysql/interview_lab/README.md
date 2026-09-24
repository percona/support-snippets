# MySQL Support Engineer Interview Lab

Browser-based, terminal-only test for MySQL DBA and Support Engineer
candidates: 11 questions, 3.5 hours, one candidate per box. The candidate opens
one URL, reads the ticket on the left, works in embedded terminals on the right,
clicks **Send**, and moves on. No SSH. No pass/fail shown to the candidate;
grading is private to the interviewer.

| You want to | Read |
|---|---|
| Build a lab, verify it, run an interview, tear it down | [`RUNBOOK.md`](RUNBOOK.md) |
| Flags and env vars of `launch-lab.sh`, `deploy.sh`, `remote-smoketest.sh`, `allow-ip.sh`, `destroy-lab.sh` | [`deploy/DEPLOY.md`](deploy/DEPLOY.md) |
| Sizing, disk, changing instance type, the AWS console by hand, "who terminated it" | [`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md) |
| The answers, and what each grader accepts and rejects | `SOLUTIONS.md` (kept outside this repo), `smoketest.sh` |
| The ticket text the candidate sees | [`candidate-exercises.txt`](candidate-exercises.txt) |
| What the lab is and how it works | this file |

This is the MySQL sibling of `mongodb/new_EC2`. The harness is shared in
spirit but the two labs are independent: different image prefix, network and
container names, and different default ports (8081 here, 8080 there), so both
run side by side on a laptop. **Not on a deployed server:** each lab's
`deploy.sh` sets `HOST_PORT=80`, so on one box only one of them can be up at a
time — `docker compose down` the other first.

## Architecture

```
                        ┌──────────────┐
  browser ── HTTP ────► │    nginx     │ ──► controller (Flask, manages state)
                        │ basic auth + │
                        │ guard inject │ ──► mysql-exercise-current-nodeN
                        └──────────────┘            │  (ttyd + mysqld)
                                                    └─ images swapped per question
```

- **nginx** — single entrypoint. Proxies `/` to the controller and
  `/term/<node>/` to that node's ttyd, injecting `static/terminal-guard.js`
  into ttyd's page. Basic auth gates the whole site; `/interviewer/` and
  `/reset` need the interviewer-only credential. Every request it forwards to
  the controller carries `X-Controller-Key`; the controller refuses requests
  without it, so a node that somehow reached it would still get a 403.
- **controller** — small Flask app on its own network (`mysql_interview_ctl`),
  never on the candidate-reachable one. Tracks the current question in
  `state/level.txt`, renders each question's `README.md` beside the terminal,
  records results, input events and file saves under `state/`, exposes
  `POST /check` and `POST /reset`, and pre-warms the next question's containers
  so transitions are quick. Drives Docker over the mounted socket. Terminal
  transcripts land on the `mysql-interview-history` volume, which it mounts
  read-only.
- **exercise-NN** — one image per question, all inheriting from
  `mysqlinterview/exercise-base` (Rocky 8 + Percona Server for MySQL 8.0 +
  Percona Toolkit + XtraBackup + ttyd + a `candidate` user). The per-question
  overlay is just `setup.sh`. Containers run privileged (systemd is PID 1),
  `auto_remove`, capped at 1 GB, on an internal network with no route to the
  internet or the controller.
- **Self-heal.** A node whose container dies (`reboot -f`, PID 1 OOM-killed)
  simply vanishes. Its terminal frame notices the dead websocket (ttyd's client
  never retries after an abnormal drop), reloads onto nginx's "Starting
  exercise" placeholder, and the placeholder asks the controller in the
  background to respawn **only the missing node**. The page, the other shells
  and unsaved Files text are untouched; the prompt is back in about a minute.
  The node reboots into the question's initial state, so replication to or
  from it has to be redone. The dashboard logs a `respawn` event.

### How submission works

`POST /check` runs the question's grader, records the result, and **advances
unconditionally** — pass or fail. The candidate sees no pass/fail signal and
cannot return to a question. Only the interviewer dashboard shows outcomes. The
button is labelled **Send** for that reason.

A failing check is re-sampled every `CHECK_INTERVAL` seconds for up to
`CHECK_SETTLE` seconds before the failure is final, because several graders
read state that is still moving when Send is pressed (an IO thread connecting,
a relay log draining, a connection pool rebuilding). Each sample is cut off at
`CHECK_TIMEOUT`, so a Q9 answer with a missing join condition cannot hold the
level lock forever.

### Where the grader lives

`check.sh` is deliberately **not** baked into the exercise image. The
candidate has passwordless `sudo` — they need it to drive `systemctl` and edit
`my.cnf` — so any grader on disk would be readable with `sudo cat`. The
controller hands `check.sh` to `bash` inside the first node at check time; it
is never written to the container's disk. For the same reason `interview-setup`
deletes `/opt/setup.sh` immediately after it runs.

What that buys: it defeats the casual `sudo cat`, not a determined candidate
who knows Docker. The containers are privileged, and root in a privileged
container can mount the host's disk, where `exercises/*/check.sh` sits because
the controller needs it. That is one reason the debrief in `RUNBOOK.md` is
mandatory, and why the answer key proper (`SOLUTIONS.md`, `smoketest.sh`)
never reaches the server.

### Controller settings

Set on the `controller` service in `docker-compose.yml`, read by
`controller/app.py`.

| Variable | Default | Meaning |
|---|---|---|
| `MAX_LEVEL` | `11` | number of questions |
| `DURATION_SECONDS` | `12600` | 3.5 h. Soft: expiry shows an overrun banner, nothing is cut off |
| `EXERCISE_MEM_LIMIT` | `1g` | per exercise container |
| `CHECK_TIMEOUT` | `20` | hard stop for one grader sample (app.py default; not set in compose) |
| `CHECK_SETTLE` | `30` | how long a failing check is re-sampled before it is final (same) |
| `CHECK_INTERVAL` | `4` | seconds between samples (same) |
| `CONTROLLER_SECRET` | `interview-lab-local-only` | the nginx→controller header value. `deploy.sh` generates a random one into `.env` on the server |
| `HOST_PORT` | `8081` (`.env`) | `deploy.sh` sets `80` |

## Layout

```
interview_lab/
├── README.md  RUNBOOK.md  candidate-exercises.txt
├── docker-compose.yml
├── .env                        # HOST_PORT (default 8081); CONTROLLER_SECRET on a server
├── nginx/nginx.conf            # nginx/auth/ holds the generated htpasswd files (git-ignored)
├── controller/
│   ├── app.py  Dockerfile  requirements.txt
│   ├── templates/{start,_briefing,index,interviewer,done,error}.html
│   └── static/{style.css,terminal-guard.js}
├── exercises/
│   ├── _base/                  # shared base image (PS 8.0 + ttyd + repl-bootstrap + employees data)
│   ├── _template/              # copy this when adding a question
│   └── 01-…/ … 11-…/           # one directory per question
├── deploy/
│   ├── bootstrap.sh            # server side: installs Docker + Compose v2
│   ├── DEPLOY.md               # script and flag reference
│   └── EC2-SETUP.md            # EC2 background: sizing, disk, console walkthrough
├── tools/
│   ├── allow-ip.sh             # open/close port 80 (or 22) to one address
│   ├── browser-test.sh         # headless Chromium through the candidate page; never deployed
│   ├── browser-test/           # its pinned Playwright (npm ci on first run)
│   ├── destroy-lab.sh          # terminate the instance and its security group
│   ├── dump-questions.sh       # regenerates candidate-exercises.txt
│   ├── fetch-employees.sh      # stages the employees sample database
│   ├── remote-smoketest.sh     # runs smoketest.sh on the server without copying it there
│   └── ws-probe.sh             # read-only terminal to test a candidate's network the day before
├── launch-lab.sh               # laptop: create the EC2 instance, deploy, optionally verify
├── deploy.sh                   # laptop: rsync + bootstrap + gen-auth + build + run over SSH
├── build.sh                    # builds base + every question image
├── gen-auth.sh                 # writes the two basic-auth files
├── smoketest.sh                # answer key + test suite; never deployed
├── run.sh                      # docker compose up
└── stop.sh                     # tear it all down
```

## The questions

| # | Question | Shape | Skill under test |
|---|----------|-------|------------------|
| 1 | The application cannot connect | discovery | service/config triage, counting one account's sessions |
| 2 | Load the customer's database | closed | tooling literacy — the floor check |
| 3 | Build a replication topology | open route | the core DBA task, plus a live package reinstall |
| 4 | The application cannot write | discovery | controlled failback, `RESET REPLICA ALL`, `super_read_only` |
| 5 | A table has stopped working | discovery | single-table recovery, `IMPORT TABLESPACE` |
| 6 | Slow reporting query | closed | index design: equality → sort → range |
| 7 | Replica falling behind | discovery | a global read lock held by a service that survives restarts |
| 8 | node3 will not start | discovery | four layered config faults, surfaced one at a time |
| 9 | Write the query | construction | composing a multi-table join, stating an assumption |
| 10 | The database is gone | open route | XtraBackup `--prepare` + `--copy-back` |
| 11 | Assess this server | assessment | diagnosis and judgement, in prose |

The five shapes are deliberate. A lab made only of "here is the defect,
remove it" tests one mode of thinking; real support work keeps changing what
it asks for. Questions 1, 4 and 5 state a *symptom* and never name the cause.
Questions 3, 6 and 10 say out loud that more than one route is accepted,
because their checks already accept several.

Question 11 is not auto-graded: the check only confirms a substantive answer
exists (the empty `human_graded` marker file tells the controller to leave it
out of the pass count; the dashboard shows **SUBMITTED — NEEDS REVIEW**) and a
human reads it. Both it and question 9 preserve what the candidate wrote onto
the transcript volume before the container is destroyed.

### The dataset

All data questions run on the genuine `employees` sample database
(datacharmer/test_db): 300k employees, 443k titles, 2.8M salaries. It is
**baked into the base image's data directory at build time**, not loaded at
container start — that keeps boot instant regardless of size and starts all
three nodes byte-identical. `tools/fetch-employees.sh` stages it; the tarball
is git-ignored. Graders assert real row counts *and* known values, so a synthetic or partial
restore fails.

The candidate-facing ticket text is in
[`candidate-exercises.txt`](candidate-exercises.txt); regenerate it with
`./tools/dump-questions.sh > candidate-exercises.txt` after editing any
exercise README.

### The answer key and the test suite

**`smoketest.sh` is the answer key** — its per-level `case` block holds the
known-good fix for every question. Read it before you interview anyone. It is
never copied to the server (`deploy.sh` excludes it, like `SOLUTIONS.md`);
`tools/remote-smoketest.sh` streams it over ssh for the run.

```bash
./smoketest.sh              # all 11 levels, then the negative cases, then security
./smoketest.sh 3 6 8        # just those levels
./smoketest.sh negative     # a known wrong fix per question must be rejected
./smoketest.sh security     # no egress, controller unreachable, transcripts written, guard injected
```

`remote-smoketest.sh` takes the same arguments. As of this writing the suite
passes 11/11, rejects all four `NEG` cases and passes all five `SEC` assertions.

The suite never touches the page. `tools/browser-test.sh` does: briefing,
Start, the terminal's websocket, the copy block, input the way browser agents
produce it (inserted in one piece, which locks the session until the interviewer
unlocks it, while typing at a person's pace goes through), Send with the Q1 fix,
a stale Send from a second tab, and any page error fails it. It starts the exam, so it
refuses once one is running, and always ends with `/reset`. It carries the Q1
fix, so `deploy.sh` excludes it too.

## Anti-cheat: what is blocked, what is allowed, what is recorded

**Blocked.** Copy and text selection on the question pane and in the
terminals, and paste in the terminals. `terminal-guard.js` blocks `copy`,
`cut`, `paste`, `selectstart`, `contextmenu`, `drop`, Shift+Insert,
Ctrl/Cmd(+Shift)+V, middle-click and Clipboard reads inside the ttyd frame,
and the frame is embedded with `allow="clipboard-read 'none'"`. The main page
blocks the same events everywhere except the Files editor and its filename
box. Input no hand produces, in a terminal or typed into the Files editor:
text inserted in one piece (how browser agents type: CDP `insertText` or a
synthetic input event, never a key press), 12 keystrokes under 20 ms apart,
more than 30 characters in a second, or 16 keys at a machine-steady beat. The
terminal guard checks the websocket frame ttyd sends to the shell, so it sees
input however it was produced; rules in `controller/static/cadence.js`. A trip
drops the input, erases the partial line (Ctrl-U), and locks the session on
the first rejection. The controller stops ttyd, refuses new terminal connections,
Files saves and Send, and shows the candidate a locked page. The interviewer
dashboard shows the time and reason, with an Unlock button; Reset also clears
the lock. Dictation trips it too; the briefing says so. Internet egress from the nodes: their network is internal, so a node
reaches its peers and nothing else — the property the whole model leans on,
and `smoketest.sh security` asserts it. Reading the grader: see "Where the
grader lives".

**Allowed on purpose.** The **Files** editor is the one place where selection,
copy and paste work. Composing `CHANGE REPLICATION SOURCE TO …` by hand tests
typing, not MySQL, so the editor lets candidates write and paste a file into
`/home/candidate` on a node. Every save is recorded with its content and where
each pasted block came from: `trivial` (under 40 chars), `question` (found in
the README), `session` (found in that node's own transcript) or `external` —
which the dashboard shows as **PASTED FROM OUTSIDE**. With copy blocked, a
candidate cannot copy from the question or a terminal, so nearly every
non-trivial paste comes from outside the lab: expect **PASTED FROM OUTSIDE**
on any substantial paste, including a legitimate statement copied from the
Percona documentation. It is a prompt for the debrief, never a verdict.

**Recorded.** A transcript per shell (`script -t`, with keystroke timing). Input
events: every rejection above, with the rule that tripped, and automation
signals at page load. The rules
acknowledgement the candidate ticked at Start, verbatim. Every file save. A
notice addressed to AI agents sits in the question pane and, hidden, in the
terminal frame; like the rejection notice, it works on an agent that honours
it, which the ones tested so far do.

**Not stopped:** an agent or autotyper that adds human-like random jitter
(xdotool, AutoHotkey, a USB keyboard emulator), screen-recording the prompt and asking another human, a phone or a
second screen, or an assistant in another window with the answer typed by
hand. There is no technical defence against those. What this gives you is a
strong signal that the candidate can *type* MySQL fluently, a full transcript
of everything they did, and the material for the controls that do cover them:
whole-screen sharing and the mandatory debrief in `RUNBOOK.md`.

## Adding a question

```bash
cp -r exercises/_template exercises/12-your-question
$EDITOR exercises/12-your-question/{README.md,setup.sh,check.sh}
./build.sh
./smoketest.sh 12
```

Then raise `MAX_LEVEL` in `docker-compose.yml` (it is `11` today), add the fix
to `smoketest.sh` so the suite keeps proving the question — and a `NEG` case
if the grader has a tempting wrong fix — a section to `SOLUTIONS.md`, and
regenerate `candidate-exercises.txt`.

The contract:
- `setup.sh` runs once at container start, after mysqld is up and the lab
  accounts exist. Break the system here. It is deleted right after it runs, so
  its comments cannot leak the answer.
- `check.sh` is injected into the first node at check time. Exit `0` = solved.
  Do not bake it into the image. Anything it must preserve for the dashboard
  goes under `$HISTDIR` (see Q9 and Q11).
- `README.md` is rendered as Markdown on the exercise page. The first line
  (`# Title`) becomes the question title.
- `nodes.txt` lists the containers to spawn, one name per line. Omit it for a
  single-node question.
- An empty `human_graded` file marks a question a person scores; the check
  then only needs to confirm something was submitted.

The lab accounts on every node: `root` with no password (local socket and
`root@'%'` for cross-node access), plus `repl`/`repl` for replication.

## Local development

Prereqs: Docker with Compose v2 on an **x86_64 Linux host**. Percona ships no
EL8 ARM64 packages for Percona Server, so this does not build on Apple
Silicon. Work from `mysql/interview_lab`; every script assumes it.

```bash
./build.sh        # the first build is 10–25 min depending on the machine; re-builds are quick
./gen-auth.sh     # prompts for a candidate password + an interviewer password
./run.sh
# → http://localhost:8081
```

Reset between runs — archives this run's state to `state/archive/<run_id>/`,
sets the level back to 1 and stops the exercise containers; transcripts are
untouched:

```bash
curl -u interviewer:<pass> -X POST http://localhost:8081/reset
```

Or click **Reset lab** on the interviewer dashboard (`/interviewer/`).

## Deploying

`RUNBOOK.md`, start to finish. Your laptop needs `ssh`, `rsync` and AWS CLI
v2; the server needs nothing preinstalled.

Nothing in this directory is secret. Passwords, keys and run state are
generated on the box and git-ignored: never commit `nginx/auth/htpasswd*`,
`.env`, `*.pem` or anything under `state/`, and never put candidate names or
transcripts in the repository.

## Notes

- One candidate at a time. Progress lives in `state/level.txt` and the
  exercise containers are shared, so two people on one box overwrite each
  other. Run one lab per candidate for parallel interviews (`LAB=` in
  `RUNBOOK.md`).
- Every question runs as a non-root `candidate` user with passwordless sudo,
  against a local mysqld with no password on root.
- Transcripts live in the `mysql-interview-history` Docker volume, one
  directory per run. The controller mounts it read-only, so `/reset` could not
  delete them if it tried. `RUNBOOK.md` shows how to export them; terminating
  the instance is what destroys them.
- `sudo reboot` inside a node fails harmlessly (`reboot.target` is masked in
  the base image). It has to: the containers are `auto_remove`, so a real
  reboot deletes the node and everything the candidate did in it. `reboot -f`
  cannot be masked; the node then comes back on its own (see Self-heal).
