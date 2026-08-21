# DBA MongoDB Interview Lab

Browser-based, terminal-only test environment for MongoDB DBA candidates.
The candidate hits a single URL, sees the exercise on the left and an
embedded terminal on the right, solves it, clicks **Check**, and advances
through 10 questions of increasing difficulty.

No SSH. No copy-paste (mostly — see Anti-cheat section).

## Architecture

```
                        ┌──────────────┐
  browser ── HTTP ────► │    nginx     │ ──► controller (Flask, manages state)
                        │  (paste-     │
                        │   blocker)   │ ──► exercise-current (ttyd + mongod)
                        └──────────────┘            │
                                                    └─ image swapped per question
```

- **nginx** — single entrypoint, proxies `/` → controller and `/term/` →
  the active exercise container. Injects a JS snippet into ttyd's HTML
  that blocks `paste`, `contextmenu`, `Shift+Insert`, middle-click,
  Ctrl/Cmd+(Shift+)V, drag-and-drop, and the Clipboard API.
- **controller** — small Flask app. Tracks the current question in
  `state/level.txt`, renders each question's `README.md` next to a terminal
  iframe, exposes `POST /check` which `docker exec`s the question's
  `check.sh` and on success swaps in the next question's image. Talks to
  the Docker daemon via the mounted socket.
- **exercise-NN** — one image per question. All inherit from
  `interview/exercise-base` (PSMDB 7.0 + mongosh + ttyd + `candidate`
  user). The per-question overlay is just `setup.sh` + `check.sh`.

Only one exercise container runs at a time, always named `exercise-current`,
so nginx's upstream is fixed.

## Layout

```
new_EC2/
├── docker-compose.yml
├── .env                        # HOST_PORT (default 8080)
├── nginx/nginx.conf
├── controller/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── templates/{index,done,error}.html
│   └── static/style.css
├── exercises/
│   ├── _base/                  # shared base image (PSMDB + ttyd + rs-bootstrap)
│   ├── _template/              # copy this when adding a question
│   └── 01-…/ … 10-…/           # one directory per question
├── tools/
│   ├── gen-company.py          # regenerates the 100k-doc percona.company fixture
│   └── dump-questions.sh       # regenerates candidate-exercises.txt
├── build.sh                    # builds base + every question image
├── smoketest.sh                # spawns each question, breaks it, fixes it, checks it
├── run.sh                      # docker compose up
└── stop.sh                     # tear it all down
```

## Local development

Prereqs: Docker (with Compose v2) on a Linux host. Tested on WSL2 Ubuntu.

```bash
./build.sh        # ~10 min the first time (base image is ~1.2 GB)
./run.sh
# → http://localhost:8080
```

Reset back to question 1 (clears progress, the scoreboard, and the timer):
```bash
curl -X POST http://localhost:8080/reset
```
Or click **Reset lab** on the interviewer dashboard (`/interviewer/`).

## Adding a question (the workflow)

```bash
cp -r exercises/_template exercises/02-create-user
$EDITOR exercises/02-create-user/{README.md,setup.sh,check.sh}
./build.sh
```

The contract:
- `setup.sh` runs once at container start, after mongod is up. Use it to
  load data, break state, create the broken scenario, etc.
- `check.sh` is what `POST /check` executes inside the container. Exit
  `0` = solved. Stdout/stderr is shown to the candidate, so make it
  helpful but don't reveal the answer.
- `README.md` is rendered as Markdown on the exercise page. The first
  line (`# Title`) becomes the question title.

## Deploying to EC2 (or any SSH server)

**Cloned this from GitHub and want your own lab? Start with
[`DEPLOYMENT.md`](DEPLOYMENT.md)** — clone, instance, deploy, verify, reset,
shut down.

The reference docs behind it:

| You have | Read |
|----------|------|
| Nothing yet, you just cloned the repo | [`DEPLOYMENT.md`](DEPLOYMENT.md) |
| No instance yet, or the old one was terminated | [`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md) |
| A server, want the deploy details and flags | [`deploy/DEPLOY.md`](deploy/DEPLOY.md) |
| A running instance, about to show it to someone | [`DEMO.md`](DEMO.md) |

**One command from your laptop** (installs Docker, sets up auth, builds, runs):

```bash
./deploy.sh ec2-user@<public-ip> -i ~/.ssh/your-key.pem
```

It rsyncs the project up, runs `deploy/bootstrap.sh` (auto-detects Amazon
Linux / Ubuntu / Rocky and installs Docker + Compose), prompts for the
candidate + interviewer passwords, then builds and starts the lab on port 80.
Full details + manual steps + caveats in [`deploy/DEPLOY.md`](deploy/DEPLOY.md).

You still need to open **port 80** in the EC2 security group to your
colleagues (and **port 22** to your own IP only).

<details>
<summary>Manual steps (what deploy.sh automates)</summary>

1. Provision an EC2 instance with Docker + Compose v2 installed. Security
   group: open **port 80** to the colleagues who will try it (ideally
   their office/VPN CIDR, not `0.0.0.0/0`), and **port 22** to *your*
   IP only.
2. Copy the project up: `scp -r new_EC2 ec2-user@<host>:~/`
3. Serve on port 80: `echo 'HOST_PORT=80' > new_EC2/.env`
4. **Create the basic-auth credentials** (required — nginx now gates the
   whole site, and `run.sh` refuses to start without them):
   ```bash
   cd new_EC2
   ./gen-auth.sh          # prompts for a candidate password + interviewer password
   ```
   This writes `nginx/auth/htpasswd` (shared candidate login) and
   `nginx/auth/htpasswd-interviewer` (interviewer-only). Both are
   git-ignored. Re-run any time to rotate, then `docker compose restart nginx`.
5. Build + run: `./build.sh && ./run.sh`
6. Share with colleagues:
   - **Candidate URL:** `http://<public-ip>/` — they log in with the
     `candidate` credential and solve the questions.
   - **Interviewer dashboard:** `http://<public-ip>/interviewer/` — the
     `interviewer` credential (candidates can't reach it). `POST /reset`
     is likewise interviewer-only.
7. Reset between colleagues — click **Reset lab** on the interviewer
   dashboard, or with the interviewer credential:
   ```bash
   curl -u interviewer:<pass> -X POST http://<public-ip>/reset
   ```
   Either way clears progress, the scoreboard, and the timer, and
   restarts at question 1.

> **TLS:** this serves plain HTTP, so basic-auth passwords cross the wire
> in the clear. Fine for a short internal demo over a trusted network;
> for anything longer put an ALB or host-level nginx with a cert in front
> and forward to port 80.

> **Single session:** there's one running exercise at a time and progress
> is shared (`state/level.txt`). For a demo where colleagues take turns
> that's fine — reset between them. For true concurrent candidates, run
> one box per candidate.

</details>

## Anti-cheat (what this stops and doesn't)

**Stops:** copy-pasting a ChatGPT answer into the terminal via Ctrl/Cmd+V,
right-click → paste, Shift+Insert, middle-click paste, dragging text
onto the terminal, and reading the system clipboard via the Clipboard
API. The instructions panel also has `user-select: none` so the
candidate can't copy the exercise text out either.

**Doesn't stop:** an OS-level autotyper (xdotool, AutoHotkey, a USB
keyboard emulator), screen-recording the prompt and asking another
human, or running a coding assistant in another window and typing the
answer by hand. There is no defense against a determined cheater short
of in-person proctoring; this gives you a strong signal that the
candidate can at least *type* mongosh commands fluently.

## Notes

- The candidate's data persists for the duration of one question — if they
  break the database mid-exercise, they can reset by closing the
  terminal tab and reopening (`auto_remove=True` means the container is
  thrown away when the controller stops it, but it survives a browser
  refresh).
- All questions run as a non-root `candidate` user. They have full mongosh
  access to a local mongod with no auth (unless the exercise's `setup.sh`
  changes that).
- `state/level.txt` is the entire candidate-progress store. Delete it (or
  `POST /reset`) to start over.
