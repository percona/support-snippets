# EC2 background

The procedure is [`../RUNBOOK.md`](../RUNBOOK.md); `launch-lab.sh` does
everything below in one command. This page is for when you need to understand
or do it by hand: the defaults, sizing, the console, disk, and forensics.

The box is disposable. It lives in a Percona sandbox account with no Elastic IP,
and sandbox accounts run scheduled cleanups, so one day the instance will not be
there. Nothing lives only on the instance except **candidate evidence**:
transcripts (the `mysql-interview-history` volume) and `state/archive/`. Export
them after every candidate (`RUNBOOK.md`, Between candidates).

## Defaults

| Item | Value | Override |
|------|-------|----------|
| Account | the Support sandbox account (id in RUNBOOK, section 1), role `sso-aws-gs-sandbox-engineer` | `AWS_PROFILE` |
| Region | `us-east-1` | `AWS_REGION` |
| Instance Name tag | `mysql-interview-lab`, or `mysql-interview-lab-<LAB>` | `NAME`, `LAB` |
| Security group | same name as the instance | `SGNAME`, `LAB` |
| Instance | `t3.large`, Amazon Linux 2023 x86_64, 30 GB gp3 | `TYPE`, `DISK`, `AMI` |
| Login user | `ec2-user` | n/a |
| SSH key | EC2 key pair `percona-interview-lab`, private key `~/.ssh/percona-interview-lab.pem` | `KEYNAME`, `KEYFILE` |

**The key pair is shared and account-level.** Terminating an instance does not
touch it. Never create a second pair for this lab: get the team's `.pem` if
yours is missing. AWS cannot re-issue a private key, so `launch-lab.sh` refuses
to run when the pair exists in EC2 but the file is missing locally.

**The security group is per lab and disposable.** `tools/destroy-lab.sh`
deletes it with the instance by default, so an ex-candidate's address is never
left allowed; `launch-lab.sh` recreates it and adds your own IP on 22 and 80.
Its rules are *source* addresses and survive stop/start.

## Sizing

| Type | vCPU | RAM | Verdict |
|------|------|-----|---------|
| `t3.large` | 2 | 8 GB | **The one to use**, and the script's default. Questions 3, 4, 7 and 8 run three Rocky containers each with its own `mysqld`, and the controller pre-warms the next question's nodes alongside them, so up to six exercise containers can be live at once, each capped at 1 GB (`EXERCISE_MEM_LIMIT`). |
| `t3.medium` | 2 | 4 GB | Boots and passes the smoke test, which runs one question at a time. In a real interview the 1 GB caps on six live containers add up to more than the machine, and the kernel kills containers when a candidate leans on one question while the next pre-warms. Only for poking at the UI. |
| `t2.micro` | 1 | 1 GB | Does not work at all. |

Arm instances fail the build: Percona ships no EL8 ARM64 packages.

Disk: 30 GB (20 is also fine, 8 is not). Measured on a fresh deploy: 3.4 GB
used, of which the images (base plus eleven question images) are 1.26 GB,
because the question images share the base layers. The reason to go above 8 GB
is the running containers: the employees dataset is baked into every node's
data directory, one question holds a full XtraBackup alongside the live datadir,
and the multi-node questions run three datadirs at once with the next
question's nodes pre-warming beside them.

## Is the instance really gone?

Do this before you create a second one. The usual reasons an instance seems to
have vanished are the wrong region in the console selector, or the instance
being stopped rather than terminated. `launch-lab.sh` checks for you and
refuses to launch over a live one.

| State | Meaning |
|---|---|
| `running` | it is there — get the IP and carry on |
| `stopped` | start it; nginx and the controller come back on their own in ~30 s (`RUNBOOK.md`, Stop, start, terminate) |
| `terminated` | gone for good; the row lingers about an hour, then disappears |
| nothing listed | terminated over an hour ago, or you are in the wrong region |

```bash
aws ec2 describe-instances \
  --filters 'Name=tag:Name,Values=mysql-interview-lab' \
  --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Launched:LaunchTime}' \
  --output table
```

In the console: **EC2 → Instances**, region **N. Virginia** (check it even if
you are sure), type `mysql-interview-lab` in the filter box, and clear any
leftover filter chip such as **Instance state = running** — that chip hides a
stopped instance and is exactly what makes a box look deleted.

### Who terminated it

Worth knowing before you rebuild, because a cleanup policy will do the same to
the new box.

```bash
aws ec2 describe-instances --instance-ids i-xxxxxxxx \
  --query 'Reservations[].Instances[].StateReason' --output json
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=TerminateInstances \
  --query 'Events[].{Time:EventTime,User:Username}' --output table
```

`Client.UserInitiatedShutdown` means a person or a script called terminate;
anything mentioning a schedule or a compliance rule is the sandbox reaper.
Console: select the instance, **Details** tab, **State transition reason**; for
the who, **CloudTrail → Event history**, lookup attribute **Event name** =
`TerminateInstances`, widen the time range. CloudTrail keeps 90 days for free.

## Creating the instance in the console

Only when the CLI is not an option; otherwise `./launch-lab.sh` (or
`NO_DEPLOY=1 ./launch-lab.sh` for the bare instance). Sign in through the
Percona access portal (`https://percona.awsapps.com/start`), pick the account
by its digits, open **Management console**, set the region to **US East (N.
Virginia) us-east-1**, then **EC2 → Instances → Launch instances**. Console
sessions expire after about an hour; re-enter through the portal when buttons
start failing.

First get your own public IP (`curl https://checkip.amazonaws.com`). Then work
down the form:

1. **Name and tags** — `mysql-interview-lab` (or `mysql-interview-lab-<LAB>`).
   That is the `Name` tag every script filters on.
2. **AMI** — Quick Start, **Amazon Linux 2023**, architecture **64-bit (x86)**.
   Not Arm.
3. **Instance type** — **t3.large**.
4. **Key pair** — **`percona-interview-lab`** from the dropdown. If it is not
   listed you are in the wrong region or account; do not create a new pair.
5. **Network settings** — click **Edit**. VPC **(default)**, subnet **No
   preference**, **Auto-assign public IP: Enable** (without it nothing can
   reach the box). Firewall:
   - The group is normally gone (`destroy-lab.sh` deletes it), so **Create
     security group**: name `mysql-interview-lab` (or `-<LAB>`), description
     `Support Engineer interview lab: HTTP + SSH`, one rule **ssh** from **My
     IP**. Then add a second rule for yourself: **HTTP**, source **My IP**.
   - If it does exist (a reaped instance, or `--keep-sg`): **Select existing
     security group**, then fix the SSH source if your IP changed
     (`./tools/allow-ip.sh --me --port 22` after launch).
   - **Leave "Allow HTTP traffic from the internet" unticked.** It writes a
     port-80 rule for `0.0.0.0/0` and `::/0`, publishing a plain-HTTP box whose
     only protection is a basic-auth password. Candidates go in one address at
     a time with `tools/allow-ip.sh`.
   - Do not leave SSH on **Anywhere** either.
6. **Configure storage** — root volume **30 GiB gp3**, **Delete on
   termination: Yes**.
7. **Advanced details** — nothing.
8. **Launch** — the **Summary** shows the type and the volume but **not the
   key pair, the public IP or the SSH source**. Scroll back and confirm the key
   pair is a real key, not **Proceed without a key pair**: it is the one
   choice you cannot change afterwards (no key = no SSH = terminate and start
   over). Confirm **Auto-assign public IP** is Enable and SSH is **My IP**.

Wait for **Running** and **2/2 checks passed** (about a minute; refresh the
list), copy **Public IPv4 address** from the **Details** tab with the copy icon
(not the Public IPv4 DNS), then from your laptop:

```bash
./deploy.sh ec2-user@<IP> -i ~/.ssh/percona-interview-lab.pem
```

and continue at `RUNBOOK.md`, step 3. To open port 80 to someone from the
console: instance → **Security** tab → the group → **Edit inbound rules → Add
rule**: **HTTP**, source **Custom** `<their IP>/32`, description = their name.
Read the existing rules first; a `0.0.0.0/0` on port 80 means the wizard's
checkbox was ticked and the lab is open to the internet right now — delete it.

## Stop, start, and the IP

Stopping keeps the EBS volume, the images and the deployed code, and bills
storage only. On start, nginx and the controller come back on their own; the
exercise containers are `auto_remove` and do not, so never stop the instance
during an interview. Do not confuse **Stop** with **Terminate** in the console
menu; they sit two rows apart and Terminate is final.

After every start the public IP is new. Re-send the URL, and clear the stale
`known_hosts` entry — a reused address with a different host key makes every
ssh attempt fail with an error that reads like a permissions problem
(`launch-lab.sh` does this for a fresh instance):

```bash
ssh-keygen -R <old-ip>
```

## Changing the instance type

No rebuild needed: stop the instance, **Actions → Instance settings → Change
instance type**, pick `t3.large`, start it. Disk, images and deployed code all
survive; the IP changes.

## Growing the disk

`df -h /` on the box. Grow the volume without recreating anything: in the
console, the instance's **Storage** tab → the volume → **Actions → Modify
volume** → 30 GiB → **Modify**. Then on the box:

```bash
sudo growpart /dev/nvme0n1 1
sudo xfs_growfs -d /
df -h /
```

## Other failures not in the runbook

- **Launched without a key pair.** No recovery path worth the effort.
  Terminate and launch again; nothing is lost, the deploy has not happened.
- **`docker` needs sudo on the box.** `bootstrap.sh` added `ec2-user` to the
  `docker` group, which takes effect at next login. Reconnect, or use `sudo`.
  `remote-smoketest.sh` exits 3 until you do.
- **Containers cannot read `state/` or `exercises/`.** SELinux enforcing — not
  on Amazon Linux 2023 (permissive), but on Rocky/RHEL `sudo setenforce 0`.
