# Interview lab runbook

MySQL Support Engineer test: 11 questions, 3.5 hours, one candidate per box.

---

## 1. Sign in

### First time only

Add the profile to `~/.aws/config`:

```ini
[profile sso-aws-gs-sandbox-engineer-482433642182]
sso_session    = percona-sso
sso_account_id = 482433642182
sso_role_name  = sso-aws-gs-sandbox-engineer
region         = us-east-1

[sso-session percona-sso]
sso_start_url  = https://percona.awsapps.com/start/#/?tab=accounts
sso_region     = us-east-1
sso_registration_scopes = sso:account:access
```

Needs AWS CLI **v2**. If the login lists no accounts, ask IT for the
`sso-aws-gs-sandbox-engineer` role on 482433642182.

Then the shared SSH key — download `percona-interview-lab.pem` and:

```bash
mv ~/Downloads/percona-interview-lab.pem ~/.ssh/
chmod 400 ~/.ssh/percona-interview-lab.pem
```

### Every time

```bash
aws sso login --profile sso-aws-gs-sandbox-engineer-482433642182
export AWS_PROFILE=sso-aws-gs-sandbox-engineer-482433642182 AWS_REGION=us-east-1
export KEYNAME=percona-interview-lab KEYFILE=~/.ssh/percona-interview-lab.pem
aws sts get-caller-identity
```

The last line prints your name if it worked.

---

## 2. Build

```bash
CAND_PASS='<candidate password>' INTV_PASS='<interviewer password>' \
  ./launch-lab.sh --smoketest
```

Creates the instance, installs the lab, opens ports 22 and 80 to you, verifies
all 11 questions, prints the URLs. ~15 min to a running lab, +~12 for the
verification, unattended. Logged to `$TMPDIR/interview-lab-<lab>-<timestamp>.log`.

Drop `--smoketest` to skip verification and run step 3 by hand later. With it,
the script exits non-zero if the lab is not fit to interview on.

Keep the instance ID and security group it prints. Every env var:
`deploy/DEPLOY.md`.

**Two interviews at once?** Name each lab — it gets its own instance *and* its
own security group, so letting one candidate in cannot expose the other's box:

```bash
LAB=ana CAND_PASS='...' INTV_PASS='...' ./launch-lab.sh
LAB=ana ./tools/allow-ip.sh <THEIR_IP> candidate
```

Pass the same `LAB=` to every command for that lab. One candidate per box
either way — the lab holds one session's state.

If the deploy fails after the instance is up, re-run just that part — you do
not need a new machine:

```bash
./deploy.sh ec2-user@<IP> -i ~/.ssh/percona-interview-lab.pem
```

---

## 3. Verify

```bash
tmux
./tools/remote-smoketest.sh ec2-user@<IP> -i ~/.ssh/percona-interview-lab.pem
```

From your laptop, not the box. ~10 min. It asks for the candidate password —
give it. Pressing Enter skips the paste-guard check, which then reports
`SKIPPED`, and a SKIPPED line is not a pass.

**Gate: 11/11 `L` lines pass, every `NEG` line `rejected`, every `SEC` line `OK`.**

| Block | Failure means |
|---|---|
| `L1`…`L11` | that question is broken — don't interview on it |
| `NEG` | the grader accepts a wrong fix |
| `SEC` | nodes can reach the internet, or you have no evidence — **stop** |

Then the candidate page itself, in a headless browser (~2 min, needs `node`).
`launch-lab.sh --smoketest` already ran it:

```bash
CAND_PASS='…' INTV_PASS='…' ./tools/browser-test.sh ec2-user@<IP> -i ~/.ssh/percona-interview-lab.pem
```

**Gate: every `C` line `OK`.** It starts the exam and resets it at the end, so
never run it while a candidate is on; it refuses once the exam has started.

---

## Before the interview

### Send the candidate this

> Before the session I need to allow your connection through the firewall.
> Open <https://ipv4.icanhazip.com> and send me the address it shows.
>
> Please do it from the same machine and network you will use for the test. If
> you will be on a VPN, connect to it first. If you will use a phone hotspot,
> be on the hotspot.
>
> On the day you will share your whole screen, camera on, for the whole
> session — the same way we screen-share on a customer call — and we finish
> with a 10–15 minute debrief on your own sessions.

Then let them in:

```bash
./tools/allow-ip.sh <THEIR_IP> candidate
./tools/allow-ip.sh --list                # who can reach it
./tools/allow-ip.sh <THEIR_IP> --revoke   # afterwards
./tools/allow-ip.sh --me                  # your own address changed
```

### Check their network reaches the terminal — the day before

```bash
ssh -i ~/.ssh/percona-interview-lab.pem ec2-user@<IP> 'cd mysql-interview-lab && ./tools/ws-probe.sh start'
```

Send them `http://<IP>/term/wstest/` with the candidate login — they should see a
`wstest` prompt in seconds. A black page while `http://<IP>/` loads means their
proxy strips WebSockets and the lab will never work from there; they need a
hotspot. Then `./tools/ws-probe.sh stop`.

### T-30

```bash
ssh -i ~/.ssh/percona-interview-lab.pem ec2-user@<IP>
cd mysql-interview-lab
df -h /                                   # ≥ 5 GB free
free -m                                   # ≥ 6 GB available
docker compose ps                         # nginx + controller Up
docker ps --filter name=mysql-exercise-   # must print nothing
curl -4 -s -o /dev/null -w '%{http_code}\n' localhost/healthz   # 200
```

Anything listed by `docker ps` means the previous session was never reset. From
that same SSH session:

```bash
curl -4 -u interviewer -X POST http://localhost/reset
```

`localhost`, not the public IP — from the box, traffic to its own public address
goes out through the internet gateway and comes back with the box's IP as the
source, which the security group does not allow. It just hangs.

### T-0

Same for every candidate, as on a customer screen-share. Page notices cannot
stop an AI side panel on their display; this can:

- Share the **entire screen**, not a tab, camera on, for the whole session.
- On it, open `chrome://extensions`; disable AI assistants and side panels.
- Think aloud, lightly: a sentence when changing approach or about to change
  something — not every keystroke.

### Show it to a colleague

Same lab, same two logins. `./tools/allow-ip.sh <THEIR_IP> <their-name>`,
reset, then send:

> If the instance is stopped, start it in the EC2 console (Instance state →
> Start); the lab comes up on its own. Take the Public IPv4 from the console —
> it changes on every start — and open `http://<IP>/` (candidate view) and
> `http://<IP>/interviewer/` (interviewer view). Logins follow separately. If
> it will not load, send me the address <https://ipv4.icanhazip.com> shows you.

Revoke their address afterwards, and reset again before a candidate.

---

## During

| URL | Who |
|---|---|
| `http://<IP>/` | candidate |
| `/interviewer/` | you — live terminal and progress, self-updating |
| `/reset` | you — **POST only** |
| `/unlock` | interviewer dashboard button — **POST only** |

The clock starts when they press Start, not when you send the link.

Never stop, reboot or resize the instance during an interview.

Require whole-screen sharing and have the candidate close AI extension side
panels. If the dashboard shows **SESSION LOCKED**, stop the interview and ask
about the rejection. Press **Unlock** only if you decide they may continue;
Reset clears the lock for the next candidate.

If the page stops loading for them mid-test, their address changed (hotspots and
VPNs rotate). Ask for it again and `./tools/allow-ip.sh <new> candidate`.

---

## After

### Debrief — 10–15 min, every candidate

Pick two transcripts from `/interviewer/`: one they passed, one that looks
interesting — a long idle gap then a perfect command, a fix with no diagnosis
before it, a `PASTED FROM OUTSIDE` flag, flags they would normally look up.
Prefer Q7 or Q8 for one, Q3 or Q10 for the other.

With copy blocked, `PASTED FROM OUTSIDE` is expected on any substantial paste,
Percona docs included. A prompt for the debrief, never a verdict.

Share your screen on the transcript and ask, letting silence do the work:

1. "Walk me through what you ran here, and why each step."
2. "What did you expect that to show? What did it actually show?"
3. "If that had come back empty, what would you have done?"
4. "What does `<flag they used>` do? What happens without it?"
5. "Where were you stuck?"

On the second, change one variable: *same lag, but an InnoDB row lock instead of
`FLUSH TABLES WITH READ LOCK` — how would you find it?* Someone who did the work
adapts; someone who was handed commands restarts.

**Good:** fluent, own words, remembers dead ends, "I checked `--help`".
**Bad** (any two are decisive): cannot explain a command they typed; the story
does not match the transcript order; generic answers where the transcript is
specific; cannot say what a flag does.

Write one line per transcript immediately. Never show pass/fail or `check.sh`.

### Between candidates

```bash
curl -4 -u interviewer:<PASS> -X POST http://<IP>/reset
```

`/reset` archives this run's state to `state/archive/<run_id>/`, sets the level
back to 1 and stops the exercise containers; transcripts are untouched. A GET
returns 405 and changes nothing, leaving the last session live.

Keep the evidence off the box — run these **from your laptop**, so the archives
land on your laptop:

```bash
ssh -i ~/.ssh/percona-interview-lab.pem ec2-user@<IP> \
  'docker run --rm -v mysql-interview-history:/h alpine tar czf - -C /h .' \
  > transcripts-$(date +%F).tgz
ssh -i ~/.ssh/percona-interview-lab.pem ec2-user@<IP> \
  'sudo tar czf - -C mysql-interview-lab/state archive' \
  > state-archive-$(date +%F).tgz
```

New passwords, if you launched with test ones or reuse the box. From your
laptop: they travel on stdin, so they never land in the server's shell history,
which a candidate can read:

```bash
printf '%s\n%s\n' '<candidate pw>' '<interviewer pw>' | ssh -i ~/.ssh/percona-interview-lab.pem ec2-user@<IP> 'cd mysql-interview-lab && ./gen-auth.sh >/dev/null && docker compose restart nginx'
```

---

## Stop, start, terminate

```bash
aws ec2 stop-instances --instance-ids <IID>        # running ~$0.08/hr; stopped ~$2.40/month
aws ec2 start-instances --instance-ids <IID>
aws ec2 wait instance-status-ok --instance-ids <IID>
aws ec2 describe-instances --instance-ids <IID> \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

**The box's IP changes on every start** — hand out the new URL. The security
group rules are *source* addresses, so they survive: nothing to re-add unless
your own or the candidate's address changed.

nginx and the controller come back on their own; exercise containers do not, so
work in the current question is lost and the clock keeps running.

Destroy it when you are finished with that candidate:

```bash
./tools/destroy-lab.sh                          # shows what it will kill; type the lab name to confirm
./tools/destroy-lab.sh -y=mysql-interview-lab   # no prompt; -y must name the lab (LAB=ana → -y=mysql-interview-lab-ana)
./tools/destroy-lab.sh --keep-sg                # leave the security group behind
```

The security group goes with it by default, so an ex-candidate's IP is never
left allowed. `launch-lab.sh` recreates it and re-adds your own access.

Termination takes the root volume with it — images, transcripts, `state/archive/`
and every other piece of evidence. Export first (Between candidates). The next
build is another ~15 minutes.

---

## When it breaks

| Symptom | Fix |
|---|---|
| `NoCredentials` / `ExpiredToken` | `aws sso login` again |
| SSH hangs | Your IP changed: `./tools/allow-ip.sh --me --port 22` |
| `launch-lab.sh`: "a lab named … already exists" | Finish it with `./deploy.sh ec2-user@<IP> …`, or `./tools/destroy-lab.sh`. `FORCE_NEW=1` only for a deliberate second box |
| Instance vanished | Sandbox reaping. Rebuild from step 2; the key pair survives, `launch-lab.sh` recreates the SG if it is gone |
| `allow-ip.sh`: "no security group named …" | Wrong or missing `LAB=`, or the lab was destroyed |
| `curl` fails, browser works | Use `curl -4` |
| Lab answers on 8081 | `.env` lost `HOST_PORT=80`. Add the line back — don't overwrite the file, it holds `CONTROLLER_SECRET` — then `docker compose up -d` |
| Lab unreachable after deploy | MongoDB lab also binds port 80. `docker compose down` the other one |
| `run.sh`: "Missing basic-auth files" | Set the passwords from your laptop, as in "New passwords" above |
| Dashboard shows a `respawn` lab event | That node's container died and came back by itself (about a minute) at the question's initial state. Tell the candidate: that node's shell and files are gone, and replication to or from it must be redone. Don't reset |
| Terminal stuck on "Starting exercise" over 2 min | On the box: `docker ps --filter name=mysql-exercise-current-` and `docker logs mysql-controller 2>&1 \| grep -i respawn` |
| A node keeps crashing after they edited its memory settings (an oversized `innodb_buffer_pool_size` on Q11, say) | mysqld OOM-looping against the 1 GB cap. The container is still up, so a reload does **not** respawn it — they revert the setting and restart mysqld, which is part of the job |
| Terminal black, page loads | Their network blocks WebSockets. Hotspot |
| Build fails / out of disk | Re-run `deploy.sh`. Disk: `docker system prune -af`; to grow the volume see `deploy/EC2-SETUP.md` |
| A question fails | `./tools/remote-smoketest.sh ec2-user@<IP> -i ~/.ssh/percona-interview-lab.pem <N>` |
| A `SEC` line fails | Do not interview. Containers can reach the internet or you have no evidence |
| A `NEG` line fails | That grader accepts a wrong fix |
| A `C` line fails | The candidate page is broken (Send, terminal, copy block) even if the suite passed. Don't interview |

⚠️ **`smoketest.sh`, `SOLUTIONS.md`, `tools/browser-test*` and every launch log are
the answer key.** Never show them to a candidate. `deploy.sh` excludes them; if
you copy the directory up by hand, delete them on the box.

Flags and env vars for every script: `deploy/DEPLOY.md`. Everything else, and
the map of the docs: `README.md`.
