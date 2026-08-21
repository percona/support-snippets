# Deploy your own copy of the interview lab

Start here if you want your own lab running on an EC2 instance. Everything is
in this directory, there is no image registry and no shared server. You end up with one box that serves the candidate page on port 80.

Budget about 30 minutes, most of it the first Docker build.

Deeper references, once you need them:

| You need | Read |
|----------|------|
| Every provisioning detail (console + AWS CLI), sizing, teardown | [`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md) |
| `deploy.sh` flags, auth modes, re-deploys | [`deploy/DEPLOY.md`](deploy/DEPLOY.md) |
| Running an actual session with a candidate | [`DEMO.md`](DEMO.md) |
| The ticket text of all 10 questions | [`candidate-exercises.txt`](candidate-exercises.txt) |

## 1. What you need

On your laptop:

- `git`, `ssh` and `rsync`.
- An AWS account you can create an EC2 instance in.

On the instance: nothing preinstalled. The bootstrap installs Docker and
Compose v2 for you.

## 2. Clone the repo

The lab lives in `mongodb/new_EC2` of the Percona support-snippets monorepo.
Clone it and work from that directory:

```bash
git clone https://github.com/percona/support-snippets.git
cd support-snippets/mongodb/new_EC2
```

Every path in this guide is relative to `mongodb/new_EC2`, and so is every
script. Run them from here, not from the repository root.

Nothing here is secret: no passwords, no keys, no state. You generate those in
step 4, and `.gitignore` keeps them out of git.

## 3. Create the EC2 instance

Amazon Linux 2023, **t3.large** (2 vCPU / 8 GB), **30 GB gp3**, one key pair.
Full walkthrough, console and CLI, in [`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md);
`deploy/create-ec2.sh` does it in one command if you have the AWS CLI configured.

Why t3.large: questions 3, 4, 5, 7 and 8 run three Rocky containers, each with
its own `mongod`. A t3.medium works but is tight, and a `t2.micro` does not.

Security group, two rules and no more:

| Port | Source | Why |
|------|--------|-----|
| 22 | **your IP only** (`x.x.x.x/32`) | your SSH access |
| 80 | your candidate's IP, or your office/VPN CIDR | the lab UI |

Do not open port 80 to `0.0.0.0/0`. The lab serves plain HTTP with basic auth,
so an open port 80 means anyone can hammer the login from the internet.

## 4. Deploy

One command, from `mongodb/new_EC2`:

```bash
./deploy.sh ec2-user@<public-ip> -i ~/.ssh/your-key.pem
```

It rsyncs the project up, installs Docker, prompts you for a **candidate** and
an **interviewer** password, sets `HOST_PORT=80`, then builds and starts
everything. The first build pulls Rocky and Percona Server for MongoDB, so it
takes about 10 minutes. Re-running it later pushes only the diffs.

Password-auth boxes and separate sudo passwords are covered by `-P` and `-K`,
see [`deploy/DEPLOY.md`](deploy/DEPLOY.md).

When it finishes it prints:

```
Candidate URL    : http://<public-ip>/             (login: candidate)
Interviewer view : http://<public-ip>/interviewer/ (login: interviewer)
```

## 5. Verify before you put a candidate in front of it

Open the candidate URL and confirm question 1 renders with a live terminal on
the right. Then, on the instance, run the smoke test. It spawns each question,
asserts `check.sh` fails on the broken state, applies the known fix, and
asserts `check.sh` passes:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<public-ip>
cd dba-interview-lab
./smoketest.sh            # all ten, ~25 minutes
./smoketest.sh 3 6 8      # or just the ones you changed
```

Every line should end in `OK`. A `FAIL` means that question would waste your
candidate's time, so fix it before the interview.

Reset to a clean state afterwards, the smoke test and your own clicking both
leave progress behind:

```bash
curl -u interviewer:<pass> -X POST http://<public-ip>/reset
```

## 6. Run a session

- Candidate opens `http://<public-ip>/` and logs in as `candidate`.
- You watch `http://<public-ip>/interviewer/`: current question, per-question
  pass/fail, attempts, elapsed time, and the terminal transcript of each node.
- **Reset lab** on that dashboard clears progress, scoreboard and timer, and
  restarts at question 1. Do it between candidates.

One candidate at a time. Progress lives in `state/level.txt` and the exercise
containers are shared, so two people on the same box overwrite each other. For
parallel interviews, run one instance per candidate.

## 7. Stop paying for it

Stopping the instance keeps the EBS volume (a few cents a month) and loses the
public IP. The lab auto-starts on boot, so **Instance state → Start** brings it
back with no SSH.

```bash
aws ec2 stop-instances  --instance-ids <id>     # between interviews
aws ec2 terminate-instances --instance-ids <id> # done for good
```

Teardown details, including the security group and key pair, are at the end of
[`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md).

## Changing the questions

Each question is a directory under `exercises/`, and the contract is three
files:

- `README.md` — the ticket the candidate reads. First line is the title.
- `setup.sh` — runs at container start, after mongod is up. This is where you
  break the system.
- `check.sh` — what **Check** runs inside node1. Exit 0 means solved. Its
  stdout is shown to the candidate, so make it useful but don't leak the fix.

`nodes.txt` lists the containers to spawn (one line per node). Rebuild with
`./build.sh` and re-test with `./smoketest.sh <n>` after any edit.

Two helpers keep the fixtures reproducible:

```bash
python3 tools/gen-company.py                 # regenerate the 100k-doc dataset
./tools/dump-questions.sh > candidate-exercises.txt   # refresh the interviewer copy
```

## Before you push your own changes back

- Never commit `nginx/auth/htpasswd*`, `.env`, `*.pem`, or anything under
  `state/`. They are git-ignored, keep it that way.
- Don't put real candidate names or transcripts in the repository.
- If you hardcode your instance's IP or passwords in a runbook for your own
  use, keep that file out of the shared repo.

## Troubleshooting

**The page says the exercise is starting and never loads.** The Rocky +
systemd + mongod containers take a minute or two to cold-boot. If it lasts
longer, check `docker logs exercise-current-node1` on the instance.

**Everything is slow, questions time out.** `free -m` on the instance. A
t3.medium running a three-node question is the usual cause.

**`run.sh` refuses to start.** The basic-auth files are missing. Run
`./gen-auth.sh`, then `docker compose restart nginx`.

**Port 80 refuses the connection from your laptop.** The security group. Add
your current IP to the inbound rule for TCP 80.

More symptoms and fixes in the troubleshooting section of
[`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md).
