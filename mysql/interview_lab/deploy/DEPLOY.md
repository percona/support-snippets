# Script reference

Flags and environment variables of the laptop-side scripts. The procedure is
in [`../RUNBOOK.md`](../RUNBOOK.md); this page only says what each knob does.
Every script prints this with `-h`.

All AWS scripts honour `AWS_PROFILE` and `AWS_REGION` (default `us-east-1`).
`LAB=<name>` namespaces a parallel lab — instance tag and security group both
become `mysql-interview-lab-<name>` — and must be passed to **every** command
for that lab.

## `launch-lab.sh`

Create the EC2 instance, deploy the lab onto it, print the URLs; with
`--smoketest`, verify it too. Refuses to launch when a lab with the same
`NAME` is already pending/running/stopping/stopped.

| Flag | Meaning |
|---|---|
| `--smoketest`, `-s` | after the deploy, run `remote-smoketest.sh` with `LAB_PASS=$CAND_PASS`, then `browser-test.sh` (skipped, and said so, without `node` or the cached Chromium); exit non-zero if anything fails |

| Variable | Default | Meaning |
|---|---|---|
| `CAND_PASS`, `INTV_PASS` | prompted (must be a terminal) | basic-auth passwords; collected here so no hidden prompt appears 30 min in |
| `LAB` | unset | parallel lab name (see above) |
| `NAME` | `mysql-interview-lab[-$LAB]` | instance `Name` tag |
| `SGNAME` | `mysql-interview-lab[-$LAB]` | security group name |
| `TYPE` | `t3.large` | instance type (`deploy/EC2-SETUP.md`, Sizing) |
| `DISK` | `30` | root volume GB, gp3, delete-on-termination |
| `AMI` | latest AL2023 x86_64 kernel-6.1 | resolved with `ec2:DescribeImages`, not SSM (the sandbox role lacks `ssm:GetParameter`) |
| `KEYNAME` | `percona-interview-lab` | EC2 key pair; must exist unless `CREATE_KEY=1` |
| `KEYFILE` | `~/.ssh/percona-interview-lab.pem` | private key; must exist locally when the pair exists in EC2 |
| `CREATE_KEY=1` | off | create the key pair and write `KEYFILE`; refuses to overwrite an existing file |
| `OPEN_HTTP` | unset | extra CIDR to allow on port 80 at launch (your own IP is always allowed on 22 and 80) |
| `FORCE_NEW=1` | off | launch even though a lab named `NAME` exists |
| `NO_DEPLOY=1` | off | stop after the instance is up and print the `deploy.sh` command |
| `LOGFILE` | `$TMPDIR/interview-lab-<timestamp>.log` | everything printed goes here as well |

Exit 2: key pair problems. Any non-zero exit after the instance exists prints
the instance ID, the `deploy.sh` command to resume, and the destroy command —
the box is billing until you act.

## `deploy.sh`

```bash
./deploy.sh user@host [-i key] [-p port] [-d remote_dir] [-P] [-K] [--keep-auth]
```

| Flag | Meaning |
|---|---|
| `-i <key>` | SSH private key (the EC2 default) |
| `-p <port>` | SSH port (default 22) |
| `-d <dir>` | remote directory (default `~/mysql-interview-lab`) |
| `-P` | password SSH auth; prompts once, needs `sshpass` locally; sudo reuses the password |
| `-K`, `--sudo-pass` | prompt for a separate sudo password |
| `--keep-auth` | preserve existing candidate and interviewer auth hashes; requires both files on the server |

`CAND_PASS` / `INTV_PASS` in the environment skip the password prompts.

Steps, over SSH: (1) `rsync -az --delete` the project, excluding `.git`,
`SOLUTIONS.md`, `smoketest.sh`, `state/`, `.env`, `.env.local`,
`nginx/auth/htpasswd*`, `__pycache__`, `*.pyc`, `*.pem`, `*.key`; (2)
`sudo deploy/bootstrap.sh` — Docker + Compose v2, distro auto-detected,
`firewalld` opened if active; (3) `gen-auth.sh` with the two passwords piped
over SSH; (4) `.env`: add a random `CONTROLLER_SECRET` if absent, set
`HOST_PORT=80`, keep everything else; (5) `sudo ./build.sh && ./run.sh`.

Idempotent: re-run to push changes and rebuild. Auth files, `.env` and
`state/` survive re-deploys. By default, re-running regenerates the auth files
from the passwords you give; `--keep-auth` preserves them instead.

Any Linux with `sudo` works: Amazon Linux 2023, Ubuntu/Debian,
Rocky/RHEL/Alma/Fedora; anything else gets the `get.docker.com` script.

## `tools/remote-smoketest.sh`

```bash
./tools/remote-smoketest.sh user@host [-i key] [-p port] [-d remote_dir] [levels|negative|security ...]
```

Streams `smoketest.sh` over ssh and runs it from a file descriptor on the
server, so the answer key never lands on the server's disk or a command line.
Same `-i`/`-p`/`-d` as `deploy.sh`. Positional arguments after the host: level
numbers, `negative` and/or `security`; no arguments runs all 11 levels, the
negative cases and security.

| Variable | Default | Meaning |
|---|---|---|
| `LAB_PASS` | prompted; Enter skips | candidate password, needed by the paste-guard assertion; without it that one line reports `SKIPPED` |
| `LAB_USER` | `candidate` | basic-auth user for that assertion |

Exit 1: usage; 2: remote dir missing; 3: the login user cannot use Docker (log
out and in after bootstrap); otherwise `smoketest.sh`'s own status.

## `smoketest.sh` (local)

```bash
./smoketest.sh                 # all 11 levels, negative cases, security
./smoketest.sh 3 6 8           # just those levels
./smoketest.sh negative        # a known wrong fix per question — all must be rejected
./smoketest.sh security        # no egress, controller unreachable, transcript written + fallback, guard injected
```

Uses its own network, container prefix and history volume; the security
section probes the *live* lab's network. `LAB_PASS`/`LAB_USER` as above.

## `tools/browser-test.sh`

```bash
./tools/browser-test.sh user@host [-i key] [-p port]
```

Headless Chromium through the candidate page: 401 without credentials,
briefing, Start, watermark and copy block, terminal websocket, agent-style
input rejected in the terminal and the Files editor, session lock and interviewer
unlock (typing at a person's pace accepted), Send with the Q1 fix (applied over ssh on stdin), a stale Send's
409, then `/reset`. Refuses when
the exam is past the briefing. Installs its pinned Playwright into
`tools/browser-test/node_modules` on first run; it uses the Chromium already
cached in `~/Library/Caches/ms-playwright` and never downloads one.

| Variable | Default | Meaning |
|---|---|---|
| `CAND_PASS`, `INTV_PASS` | prompted | the two basic-auth passwords |
| `DRY=1` | off | only the 401/page-renders case; changes nothing |
| `FORCE=1` | off | reset a started exam first, then run. Never during an interview |

Exit 0: all `C` lines OK; 1: a case failed (screenshots in
`tools/browser-test/output/<host>/`); 2: refused or wrong password; 3: no Chromium
(`cd tools/browser-test && npx playwright install chromium`).

## `tools/allow-ip.sh`

```bash
./tools/allow-ip.sh <IP|CIDR> [description]   # allow on port 80; description defaults to "candidate"
./tools/allow-ip.sh <IP|CIDR> --revoke
./tools/allow-ip.sh --me [--port 22]           # your current public IP
./tools/allow-ip.sh --list
```

A bare IPv4 gets `/32`. Refuses IPv6 (the lab has none) and `0.0.0.0/0`. Any
AWS error other than duplicate/absent rule is fatal, so "already allowed" is
never printed over a failure. `SGNAME` overrides the group name.

## `tools/destroy-lab.sh`

```bash
./tools/destroy-lab.sh                          # lists what will go, asks you to type the lab name
./tools/destroy-lab.sh -y=mysql-interview-lab   # no prompt; the value must equal NAME
./tools/destroy-lab.sh --keep-sg                # do not delete the security group
./tools/destroy-lab.sh --all                    # when several instances carry the name
```

Terminates every instance tagged `NAME`, waits, then **deletes the security
group** (retrying for a minute while the ENI detaches; exits 1 if it cannot).
Refuses when more than one instance carries the name unless `--all`. `NAME`
and `SGNAME` override the defaults. The root volume goes with the instance:
images, transcripts and `state/archive/` included — export first
(`RUNBOOK.md`, Between candidates).

## Manual deploy

```bash
rsync -az -e 'ssh -i ~/.ssh/percona-interview-lab.pem' \
      --exclude .git --exclude SOLUTIONS.md --exclude smoketest.sh \
      --exclude state/ --exclude .env --exclude .env.local --exclude 'nginx/auth/' \
      --exclude __pycache__ --exclude '*.pyc' --exclude '*.pem' --exclude '*.key' \
      ./ ec2-user@<host>:~/mysql-interview-lab/
ssh -i ~/.ssh/percona-interview-lab.pem ec2-user@<host>
cd mysql-interview-lab
sudo bash deploy/bootstrap.sh        # install docker
./gen-auth.sh                        # set the two passwords
echo 'HOST_PORT=80' > .env
echo "CONTROLLER_SECRET=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" >> .env
sudo ./build.sh && sudo ./run.sh     # VERBOSE=1 ./build.sh streams every image's full output
```

`SOLUTIONS.md` and `smoketest.sh` are the answer key and a candidate is root
in a privileged container that can reach the host's disk; `*.pem` would hand
them your SSH key. If you `scp -r` instead, delete all of them on the box.

## Caveats

- **Plain HTTP.** Basic-auth passwords cross the wire in the clear. Open port
  80 per IP, never to `0.0.0.0/0`; for anything longer than an interview put
  TLS (ALB or host nginx) in front.
- **SELinux enforcing** (Rocky/RHEL): the controller bind-mounts the Docker
  socket and `state/`/`exercises/`. If containers cannot read them,
  `sudo setenforce 0`. Amazon Linux 2023 ships permissive.
- **Cold boot.** Rocky + systemd + mysqld containers take a minute or two; the
  candidate page auto-refreshes until ready.
