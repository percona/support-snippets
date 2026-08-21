# Deploying the Support Engineer Interview Lab

Deploy to any server you can reach over SSH (EC2, a VPS, a bare box) with one
command from your laptop.

> Need to create the EC2 instance first, or the old one is gone?
> [`EC2-SETUP.md`](EC2-SETUP.md) covers provisioning, verification, the security
> group, and teardown. This file covers `deploy.sh` itself.

## Prerequisites

**On the server:**
- A fresh Linux box — Amazon Linux 2023, Ubuntu/Debian, or Rocky/RHEL/Alma
  (anything else falls back to the official Docker install script).
- A user with `sudo`. Passwordless `sudo` (the EC2 default) needs no flags;
  otherwise pass the sudo password with `-K` (or `-P`, which reuses the login
  password). Docker does not need to be pre-installed — the bootstrap does it.
- Inbound **TCP 80** open to your colleagues (EC2 security group, or host
  firewall). Open **TCP 22** only to your own IP.

**On your laptop:**
- `ssh` and `rsync` installed.
- Either your SSH key for the server, or `sshpass` installed if you use `-P`
  for password auth.

## One command

```bash
./deploy.sh ec2-user@<public-ip> -i ~/.ssh/your-key.pem
```

### Auth modes / flags

| Flag | Meaning |
|------|---------|
| `-i <key>` | SSH private key (key-based auth — the EC2 default). |
| `-P` | **Password SSH auth.** Prompts once for the login password. Requires `sshpass` on your laptop (`apt/dnf/brew install sshpass`). sudo reuses the same password by default. |
| `-K` | Prompt for a **separate sudo password** (use if sudo differs from the login password, or with a key-auth box whose sudo still needs one). |
| `-p <port>` | SSH port (default 22). |
| `-d <dir>` | Remote directory (default `~/dba-interview-lab`). |

**Username/password server (no key):**
```bash
./deploy.sh user@host -P            # type the password once; sudo reuses it
```
If you'd rather not depend on `sshpass`, install your key once and drop `-P`:
```bash
ssh-copy-id -i ~/.ssh/your-key.pub user@host   # type password this one time
./deploy.sh user@host -i ~/.ssh/your-key
```

That will, over SSH:

1. **rsync** the project to `~/dba-interview-lab` on the server
   (excludes local state, the basic-auth secrets, and caches).
2. Run `deploy/bootstrap.sh` — installs **Docker + Compose v2**, auto-detecting
   the distro, enables the service, and opens port 80 if `firewalld` is active.
3. Prompt you for a **candidate** password and an **interviewer** password,
   then generate the nginx basic-auth files on the server (passwords are piped
   over SSH, never written to your laptop).
4. Set `HOST_PORT=80`, then `build.sh` + `run.sh`.

Flags: `-i <keyfile>`, `-p <ssh-port>`, `-d <remote-dir>`.

When it finishes it prints the URLs:

```
Candidate URL    : http://<public-ip>/             (login: candidate)
Interviewer view : http://<public-ip>/interviewer/ (login: interviewer)
```

## Re-deploying after changes

Just run `./deploy.sh ...` again. rsync pushes only the diffs and rebuilds.
The server's basic-auth files and run state are excluded from `--delete`, so
they survive re-deploys. To rotate passwords, re-run and it regenerates them
(then restarts nginx via the build/run step).

## Resetting between candidates

Click **Reset lab** on the interviewer dashboard
(`http://<public-ip>/interviewer/`), or with the interviewer credential:

```bash
curl -u interviewer:<pass> -X POST http://<public-ip>/reset
```

Either way clears all progress, the scoreboard, and the timer, and
restarts at question 1.

## Manual deploy (if you prefer not to use deploy.sh)

```bash
scp -r -i key.pem ../new_EC2 ec2-user@<host>:~/dba-interview-lab
ssh -i key.pem ec2-user@<host>
cd dba-interview-lab
sudo bash deploy/bootstrap.sh        # install docker
./gen-auth.sh                        # set the two passwords
echo 'HOST_PORT=80' > .env
sudo ./build.sh && sudo ./run.sh
```

## Caveats

- **Plain HTTP.** Basic-auth passwords cross the wire in the clear. Fine for a
  short internal demo on a trusted network; for anything longer, put an ALB or
  host nginx with a TLS cert in front and forward to port 80.
- **SELinux (Rocky/RHEL enforcing).** The controller bind-mounts the Docker
  socket and the `state`/`exercises` dirs. If containers can't read them, set
  the box permissive for the demo: `sudo setenforce 0`. Amazon Linux 2023 ships
  permissive by default, so this usually isn't needed there.
- **Single session.** One running exercise at a time, shared progress. For
  colleagues taking turns, reset between them; for true concurrency, one box
  per candidate.
- **First boot is slow.** The Rocky+systemd+mongod exercise containers take a
  minute or two to cold-boot; the candidate page auto-refreshes until ready.
