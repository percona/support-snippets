# Lab demo runbook (EC2)

How to show the interview lab to colleagues.

> This assumes the instance exists. If it is missing or terminated (sandbox
> accounts get reaped), rebuild it with
> [`deploy/EC2-SETUP.md`](deploy/EC2-SETUP.md).

## Instance
- **Name:** `<instance-name>` (AWS EC2, Amazon Linux 2023, t3.medium, 20 GiB gp3)
- **SSH:** `ssh -i ~/.ssh/<your-key>.pem ec2-user@<ip>`
- **Public IP is dynamic**, it changes every stop/start unless you attach an
  Elastic IP. Grab the current Public IPv4 from the EC2 console after starting.

## Auto-start
The lab comes up by itself on boot, no SSH or `run.sh` needed:
- containers (`dba-nginx`, `dba-controller`) have `restart: unless-stopped`
- the `docker` service is `enabled` on boot
- per-question node containers spin up on demand when a candidate starts a question

So: **Instance state → Start instance**, wait ~30s, done.

## URLs + credentials
- Candidate view:    `http://<ip>/`             — login `candidate` / `<candidate-password>`
- Interviewer view:  `http://<ip>/interviewer/`  — login `interviewer` / `<interviewer-password>`

Both passwords are the ones you chose when `deploy.sh` prompted for them (or that
you passed as `CAND_PASS` / `INTV_PASS`). The interviewer cred also works on the
candidate site. Never commit them, `nginx/auth/htpasswd*` is git-ignored for that
reason. Rotate them with the command below.

## Before a demo
- **Reset progress** for a clean start: "Reset lab" button in `/interviewer/`,
  or `curl -u interviewer:<interviewer-password> -X POST http://<ip>/reset`
- **Security Group** must allow inbound **TCP 80** from the viewers' IPs
  (and TCP 22 from yours). Set in EC2 console → instance's Security Group → Inbound rules.
  The lab is plain HTTP with basic auth, so do not open :80 to `0.0.0.0/0`.

## Rotate passwords
```
ssh -i ~/.ssh/<your-key>.pem ec2-user@<ip> \
  'cd dba-interview-lab && CANDIDATE_PASS=... INTERVIEWER_PASS=... ./gen-auth.sh \
   && sudo docker compose restart nginx'
```

## Message to send a colleague
> Hey! If you want to check out the new EC2 interview lab, just start the instance
> in the EC2 console (Instance state → Start). The lab auto-starts on boot, so
> nothing else to do.
>
> Once it's running, grab the Public IPv4 from the console (it changes each restart)
> and open:
> - http://<instance-ip>/ — candidate view
> - http://<instance-ip>/interviewer/ — interviewer view
>
> I'll send you the two logins separately. Just work through the questions and let
> me know what you think. (If it won't load, the Security Group needs inbound port
> 80 open to your IP.)
