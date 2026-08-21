# Creating the EC2 instance for the interview lab

The lab box is disposable. It lives in a Percona sandbox account, it has no
Elastic IP, and sandbox accounts run scheduled cleanups, so sooner or later you
will open the EC2 console and the instance will not be there. That is the
problem this guide solves: going from nothing to a working lab URL in about 20
minutes, without remembering any of it.

Nothing about the lab lives only on the instance. The images are built from this
repo, and the only server-side state is candidate progress, which you reset
before every demo anyway. Losing the box costs you the build time and nothing
else.

Related docs:

- [`DEPLOY.md`](DEPLOY.md) covers `deploy.sh` itself, its auth flags, and the caveats.
- [`../DEMO.md`](../DEMO.md) is the runbook for an instance that already exists.
- This guide is for when the instance does not exist yet.

## The account

Fill these in for your own AWS account before you start. Every one of them is an
environment override on `create-ec2.sh`, so nothing here is hardcoded.

| Item | Value | Override |
|------|-------|----------|
| AWS profile | your AWS CLI profile | `AWS_PROFILE` (default: your CLI default) |
| Region | `us-east-1` | `AWS_REGION` |
| Instance Name tag | `dba-interview-lab` | `NAME` |
| Login user | `ec2-user` (Amazon Linux 2023) | n/a |
| SSH key | `~/.ssh/dba-interview-lab.pem`, EC2 key pair `dba-interview-lab` | `KEYFILE`, `KEYNAME` |

A key pair does not outlive the instance it was created for unless you
deliberately keep it. After a rebuild, check which pair the current box actually
uses instead of assuming the old `.pem` still works.

Sandbox accounts are not permanent infrastructure. Assume anything you leave
running can be terminated without notice, and never store something in the lab
that you cannot rebuild from this repo.

## Two paths through this guide

Every step below is written twice, **In the console** and **With the CLI**. Pick
one and stay on it. The console path needs nothing installed and is the one to
use when the SSO token has expired or you just want to see what you are doing.

Steps 3, 4, and 6 (deploy, verify, hand over) are terminal work either way,
because `deploy.sh` runs from your laptop over SSH.

## Step 0: log in

### In the console

1. Open your organization's AWS access portal (`https://<your-org>.awsapps.com/start`)
   and sign in with SSO.
2. You land on a list of accounts. Expand the one you use for this lab. The portal
   shows accounts by name and ID, not by the profile name in your `~/.aws/config`,
   so match on the account digits.
3. Under the account, click your role, then **Management console**. That opens the
   AWS console in a new tab.
4. **Set the region.** Top right, next to your account name, is the region
   selector. Choose **US East (N. Virginia) us-east-1**. Everything for this lab
   lives there, and the console remembers the last region you used, so this is
   the single most common reason an instance looks like it disappeared.
5. In the top search bar, type `EC2` and click the **EC2** service result. Then
   **Instances** in the left sidebar.

Console sessions time out after an hour or so. When buttons start failing, go
back to the access portal and re-enter.

### With the CLI

The SSO token expires often. Every terminal session starts here:

```bash
aws sso login --profile <your-aws-profile>
```

Confirm it worked:

```bash
$ aws sts get-caller-identity --profile <your-aws-profile>
{
    "Account": "<your-account-id>",
    ...
}
```

To save typing on every command that follows:

```bash
export AWS_PROFILE=<your-aws-profile>
export AWS_REGION=us-east-1
```

## Step 1: check whether the instance is really gone

Do this before you create a second one. The usual reasons an instance seems to
have vanished are the wrong region in the console selector, or the instance
being stopped rather than terminated.

You are after one field, the instance state. What each value means:

- **`running`**: it is there. Get the IP and go to [`../DEMO.md`](../DEMO.md).
- **`stopped`**: start it and wait about 30 seconds. The lab auto-starts, so
  there is nothing to rebuild. **Instance state**, **Start instance** in the
  console, or `aws ec2 start-instances --instance-ids i-xxxxxxxx`.
- **`terminated`**: it is gone for good. Terminated instances stay listed for
  about an hour, then disappear entirely. Continue with this guide.
- **Nothing found at all**: either it was terminated over an hour ago, or you are
  looking at the wrong region.

### In the console

1. **EC2**, then **Instances** in the left sidebar.
2. Confirm the region is **N. Virginia** (top right). Check this even if you are
   sure. Especially if you are sure.
3. The instance list has a filter box above it. Type `dba-interview-lab` and press
   Enter.
4. Clear any leftover filter chips under the search box, for example
   **Instance state = running**. A chip like that hides a stopped instance and is
   exactly what makes a box look deleted.
5. Look at the **Instance state** column.

To see the termination reason, select the instance, open the **Details** tab, and
read **State transition reason** and **State transition message**. For who did
it, search **CloudTrail** in the top bar, open **Event history**, set the
lookup attribute to **Event name** = `TerminateInstances`, and widen the time
range. CloudTrail keeps 90 days of event history for free.

### With the CLI

```bash
aws ec2 describe-instances \
  --filters 'Name=tag:Name,Values=dba-interview-lab' \
  --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Launched:LaunchTime}' \
  --output table
```

If it was terminated, the reason is worth reading before you rebuild, because a
cleanup policy will do the same thing to the new instance:

```bash
aws ec2 describe-instances --instance-ids i-xxxxxxxx \
  --query 'Reservations[].Instances[].StateReason' --output json
```

`Client.UserInitiatedShutdown` means a person or a script called terminate.
Anything mentioning a schedule or a compliance rule is the sandbox reaper. You
can also check who did it, if CloudTrail is readable in the sandbox:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=TerminateInstances \
  --query 'Events[].{Time:EventTime,User:Username}' --output table
```

## Step 2: create the instance

### In the console

First, get your own public IP, because the SSH rule needs it. In a terminal:

```bash
$ curl https://checkip.amazonaws.com
203.0.113.7
```

Or open https://checkip.amazonaws.com in a browser. Keep that number to hand.

Now, in **EC2**, then **Instances**, click the orange **Launch instances** button
in the top right. The launch page is one long form. Work down it in order.

**1. Name and tags**

- **Name:** `dba-interview-lab`

That writes the `Name` tag, which is what step 1's filter searches for. Skip
**Add additional tags**.

**2. Application and OS Images (Amazon Machine Image)**

- In the **Quick Start** tabs, **Amazon Linux** is selected by default.
- **Amazon Machine Image:** leave the default **Amazon Linux 2023 AMI**. It will
  say `ami-0…` with **Free tier eligible** next to it.
- **Architecture:** **64-bit (x86)**. Do not switch to Arm. The lab images are
  built for x86_64, and an Arm instance will fail the build.

**3. Instance type**

- Click the dropdown and choose **t3.large** (2 vCPU, 8 GiB). See
  [Sizing](#sizing) below.
- It is not free-tier eligible, and that is fine in a sandbox account. Stop the
  instance when you are not using it.

**4. Key pair (login)**

- **Key pair name:** pick **`dba-interview-lab`** from the dropdown, the pair the
  current box uses. You have the matching private key at
  `~/.ssh/dba-interview-lab.pem`.
- **If it is not in the list**, the key pair went away with the instance it
  belonged to, and your local `.pem` is now useless. AWS cannot re-issue a
  private key. Click **Create new key pair**:
  - **Name:** something new, for example `dba-interview-lab2`. Do not reuse a name
    whose local `.pem` you still have, or you will not know which file is live.
  - **Type:** RSA. **Format:** `.pem`.
  - **Create key pair** downloads the file, once. AWS never shows it again.
  - On WSL2 the download lands on the Windows side. Move it and fix the
    permissions, or SSH will refuse to use it, and so will `deploy.sh`:
    ```bash
    mv ~/Downloads/dba-interview-lab2.pem ~/.ssh/
    chmod 400 ~/.ssh/dba-interview-lab2.pem
    ```
  - Keep it in `~/.ssh/`, never in the project directory. `deploy.sh` rsyncs the
    project to the server, so a `.pem` sitting there would be copied to the box.
    It now excludes `*.pem` and `*.key`, but the habit is the real protection.
  - Use that new path everywhere `~/.ssh/dba-interview-lab.pem` appears below.

**5. Network settings**

Click **Edit** on the right of this panel to see the real fields.

- **VPC:** the one marked **(default)**.
- **Subnet:** **No preference**.
- **Auto-assign public IP:** **Enable**. Without this the box has no public
  address and nothing can reach it.
- **Firewall (security groups):**
  - **If `dba-interview-lab` already exists** (it survives instance termination):
    choose **Select existing security group** and tick **`dba-interview-lab`**.
    Note that its SSH rule points at whatever your IP was last time, so if your
    IP has changed since, fix it in step 5.
  - **If it does not exist:** choose **Create security group** and fill in:
    - **Security group name:** `dba-interview-lab`
    - **Description:** `Support Engineer interview lab: HTTP + SSH`
    - You get one default inbound rule. Set **Type** = **ssh**, **Source type** =
      **My IP**. The console fills in your current address as a `/32`.
    - **Leave "Allow HTTP traffic from the internet" unticked.** The wizard shows
      that checkbox right below the rules, and ticking it writes a port 80 rule
      for `0.0.0.0/0` and `::/0`. That publishes a plain-HTTP box, whose only
      protection is a basic-auth password you also wrote down in `DEMO.md`, to
      anyone who scans the address range. Port 80 goes in at step 5, per viewer.
    - Do not leave SSH on `0.0.0.0/0` (**Anywhere**) either.

**6. Configure storage**

- Change the root volume from the default **8 GiB** to **30 GiB**, type **gp3**.
  20 GiB is also fine.
- Measured on a fresh deploy: **3.4 GB used**, of which all eleven images are
  1.26 GB, because the ten question images share the base layers. The reason to go
  above 8 GiB is not the images, it is the running containers. Question 5 has the
  candidate grow an oplog to 5 GB, question 10 restores a backup, and the
  multi-node questions run three data directories at once.
- Leave **Delete on termination** as **Yes**, so a terminated instance does not
  leave an orphan volume billing quietly in the account.

**7. Advanced details**

Nothing to change. Skip it.

**8. Launch**

- The **Summary** panel on the right should read: 1 instance, Amazon Linux 2023,
  **t3.large**, New or existing security group, **1 volume, 30 GiB**. Fix any of
  those that disagree before launching.
- **The Summary does not show the key pair.** Scroll back up to the **Key pair
  (login)** panel and confirm it names a real key and not **Proceed without a key
  pair**. Of everything on this page, that is the only choice you cannot change
  after the fact: no key means no SSH, so no deploy, and the only fix is to
  terminate and start over. The instance type and the volume size are both
  editable later.
- **Auto-assign public IP** and the SSH rule are also hidden from the Summary.
  Both live behind **Edit** in Network settings. Confirm the IP is **Enable** and
  the SSH source is **My IP**, not **Anywhere**.
- Click **Launch instance**, then **View all instances**.
- Wait for **Instance state** = **Running** *and* **Status check** = **2/2
  checks passed**. That takes about a minute. Refresh the list, it does not
  always update on its own.
- Select the instance and copy **Public IPv4 address** from the **Details** tab.
  Use the copy icon, not a manual selection, and do not grab the **Public IPv4
  DNS** by mistake.

That IP is what goes into step 3. It changes on every stop and start.

### With the CLI

From the project root:

```bash
./deploy/create-ec2.sh
```

It resolves the current Amazon Linux 2023 AMI from the SSM public parameter,
reuses the `dba-interview-lab` key pair and the `dba-interview-lab` security group if they
exist, opens SSH to your current public IP only, launches the instance, waits
for status checks, and prints the IP plus the exact `deploy.sh` command.

Useful overrides:

```bash
TYPE=t3.medium ./deploy/create-ec2.sh          # smaller box, see sizing below
CREATE_KEY=1 ./deploy/create-ec2.sh            # key pair missing from EC2 too
OPEN_HTTP=203.0.113.7/32 ./deploy/create-ec2.sh  # open port 80 right away
NAME=lab-ana ./deploy/create-ec2.sh            # a second box for a second candidate
```

The script always launches a new instance, so run step 1 first. It stops with a
clear error if the key pair is missing and you did not pass `CREATE_KEY=1`,
because creating one would write over your local `.pem`.

### Sizing

| Type | vCPU | RAM | Verdict |
|------|------|-----|---------|
| `t3.medium` | 2 | 4 GB | Works, but tight. Questions 3, 4, 5, and 7 run three Rocky containers each with its own `mongod`. |
| `t3.large` | 2 | 8 GB | The default here. Comfortable for the multi-node questions. |

Disk: 30 GB. The base image alone is about 1.2 GB, the per-question images layer on
top of it, and the FTDC question ships real diagnostic data.

## Step 3: deploy the lab

One command from your laptop, from the project root:

```bash
./deploy.sh ec2-user@<new-ip> -i ~/.ssh/dba-interview-lab.pem
```

It rsyncs the project to `~/dba-interview-lab`, installs Docker and Compose v2
via `deploy/bootstrap.sh`, prompts for the candidate and interviewer passwords,
writes `HOST_PORT=80`, then builds and starts everything. Full flag reference in
[`DEPLOY.md`](DEPLOY.md).

Expect roughly 10 to 15 minutes, almost all of it building the base image.

It prompts for the candidate and interviewer passwords. Reuse the ones your
colleagues already have, or pick new ones and re-send the URLs. To script it:

```bash
CAND_PASS=<candidate-password> INTV_PASS=<interviewer-password> \
  ./deploy.sh ec2-user@<new-ip> -i ~/.ssh/dba-interview-lab.pem
```

The passwords never land on disk in this repo. `gen-auth.sh` writes only apr1
hashes into `nginx/auth/`, which is git-ignored.

## Step 4: verify before you invite anyone

Three checks, cheapest first.

**1. The site answers and auth is on.** Run these on the box, so the result does
not depend on your security group:

```bash
ssh -i ~/.ssh/dba-interview-lab.pem ec2-user@<new-ip>
[ec2-user@ip-10-0-0-1 ~]$ curl -o /dev/null -s -w '%{http_code}\n' localhost
401
[ec2-user@ip-10-0-0-1 ~]$ curl -o /dev/null -s -w '%{http_code}\n' -u candidate:<candidate-password> localhost
200
[ec2-user@ip-10-0-0-1 ~]$ curl -o /dev/null -s -w '%{http_code}\n' -u candidate:<candidate-password> localhost/interviewer/
401
[ec2-user@ip-10-0-0-1 ~]$ curl -o /dev/null -s -w '%{http_code}\n' -u interviewer:<interviewer-password> localhost/interviewer/
200
```

Read it as: locked without credentials, open to the candidate on the candidate
site, **locked to the candidate on the dashboard**, open to the interviewer. The
dashboard is a second `auth_basic` realm, so a candidate who is already
authenticated site-wide still gets a `401` challenge there rather than a `403`.

The third line is the one that matters. If it returns `200`, the
interviewer-only htpasswd was not generated, and candidates can read the
dashboard and reset their own progress.

**1b. Check what the outside world can reach.** From your laptop, not the box:

```bash
$ curl -o /dev/null -s -w '%{http_code}\n' http://<new-ip>/
401
```

A `401` means port 80 is open to you and basic auth is doing its job. A timeout
means port 80 is closed, which is the safe default this guide aims for. Either is
fine, as long as you know which one you have, and as long as "open to you" is not
actually "open to everyone" (see step 5).

**2. The containers are up and set to restart.**

```bash
[ec2-user@ip-10-0-0-1 ~]$ cd dba-interview-lab && sudo docker compose ps
```

`dba-nginx` and `dba-controller` should both be `Up`. Confirm the boot path:

```bash
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ systemctl is-enabled docker
enabled
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ sudo docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' dba-nginx dba-controller
unless-stopped
unless-stopped
```

Those two facts are the whole reason you can tell a colleague "just start the
instance, the lab comes up by itself". If either is wrong, the message is a lie
and they will hit a dead port.

**3. The questions actually solve.** `smoketest.sh` spawns each question, asserts
`check.sh` fails in the broken state, applies the fix, and asserts it passes.
The full run takes a while, so start with the fast ones:

```bash
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ ./smoketest.sh 1 2 6
```

Then, if you have the time, all ten:

```bash
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ ./smoketest.sh
```

Every line in the summary should read `OK`. Run it before a demo, not during
one.

## Step 5: open port 80 to your viewers

Do this last, and per IP rather than to the world. The lab is plain HTTP, so
basic-auth passwords cross the wire in the clear.

Ask the colleague for their IP first. Have them open
https://checkip.amazonaws.com and send you what it prints. Their office IP is
not what you want if they are on a VPN, and the browser check gives you the
address they will actually arrive from.

### In the console

1. **EC2**, **Instances**, select `dba-interview-lab`.
2. Open the **Security** tab, then click the security group link
   (`sg-…  dba-interview-lab`).
3. **Read the existing inbound rules before adding anything.** If port 80 already
   shows a source of `0.0.0.0/0` or `::/0`, the launch wizard's "Allow HTTP
   traffic from the internet" checkbox was ticked and the lab is open to the
   internet right now. Delete those two rules and replace them with the per-IP
   rule below.
4. On the **Inbound rules** tab, click **Edit inbound rules**.
4. **Add rule**:
   - **Type:** **HTTP**. Port 80 fills in automatically.
   - **Source type:** **Custom**, and in the box next to it type their address
     with `/32` on the end, for example `203.0.113.7/32`.
   - **Description:** their name. You will thank yourself when you clean up.
5. **Save rules**. It takes effect within seconds, no instance restart.

To close it afterwards, same screen, click **Delete** on that rule, then
**Save rules**.

While you are in there, check the existing **SSH** rule still lists *your*
current IP. Home IPs change, and a stale rule is why SSH suddenly times out.

### With the CLI

```bash
aws ec2 authorize-security-group-ingress \
  --group-name dba-interview-lab \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=203.0.113.7/32,Description=colleague-name}]'
```

Then confirm from your own machine:

```bash
$ curl -o /dev/null -s -w '%{http_code}\n' -u candidate:<candidate-password> http://<new-ip>/
200
```

Revoke it when the demo is over:

```bash
aws ec2 revoke-security-group-ingress \
  --group-name dba-interview-lab \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=203.0.113.7/32}]'
```

## Step 6: hand it over

Reset first, so they start at question 1 with a clean scoreboard and timer:

```bash
curl -u interviewer:<interviewer-password> -X POST http://<new-ip>/reset
```

Then send the URLs. The message template is at the bottom of
[`../DEMO.md`](../DEMO.md). Remember to update the IP in `DEMO.md`, because it
changes on every stop and start.

## Stopping, starting, and the IP

Stop the instance when nobody is using it. You keep the EBS volume, the built
images, and the deployed code, and you pay for storage only.

In the console: select the instance, then **Instance state** in the top right,
then **Stop instance** or **Start instance**. Confirm in the dialog. A start
takes about 30 seconds to reach **Running**, and the lab comes up on its own
from there.

With the CLI:

```bash
aws ec2 stop-instances  --instance-ids i-xxxxxxxx
aws ec2 start-instances --instance-ids i-xxxxxxxx
```

Do not confuse **Stop** with **Terminate** in that menu. They sit two rows
apart, and Terminate is final.

After every start, the public IP is new. Two consequences:

- Re-send the URL, and update `DEMO.md`.
- Your SSH known_hosts entry for the old IP may now point at someone else's box,
  and reused IPs make SSH complain about a changed host key. Clear the stale
  entry:
  ```bash
  ssh-keygen -R <old-ip>
  ```

The security group rules survive a stop and start, so you do not redo step 5.

## Tearing it down

In the console: select the instance, **Instance state**, **Terminate (delete)
instance**, then confirm. The row stays visible as `terminated` for about an
hour, then vanishes.

With the CLI:

```bash
aws ec2 terminate-instances --instance-ids i-xxxxxxxx
```

The root volume has `DeleteOnTermination=true`, so the disk goes with it. The
key pair and the security group stay behind, which is what makes the next
rebuild quick. Nothing to back up first, unless you want a candidate's
transcript from the interviewer dashboard.

## Troubleshooting

**`aws` says the token expired.** Re-run step 0. The SSO session is short.

**The browser hangs on `http://<ip>/`.** Port 80 is not open to that viewer's
IP. Step 5. Confirm the rule matches the IP they actually come from, which is
not their office IP if they are on a VPN.

**SSH times out.** Your own IP changed, so the SSH rule no longer matches.
Re-run `./deploy/create-ec2.sh` against the existing group, or add the rule by
hand with port 22 and your new `/32`.

**`run.sh` refuses to start: missing basic-auth files.** `gen-auth.sh` never
ran, or its output was excluded from the rsync. Fix it on the box:

```bash
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ CANDIDATE_PASS=<new-candidate-password> INTERVIEWER_PASS=<new-interviewer-password> ./gen-auth.sh
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ sudo docker compose restart nginx
```

**The candidate page keeps refreshing and never shows a terminal.** Normal for
the first minute or two of a question. The exercise containers boot Rocky with
systemd and wait for `mongod`. If it lasts longer, look at the controller:

```bash
[ec2-user@ip-10-0-0-1 dba-interview-lab]$ sudo docker logs --tail 50 dba-controller
```

**Containers cannot read `state/` or `exercises/`.** SELinux enforcing. Amazon
Linux 2023 ships permissive, so you should not hit this here, but on Rocky or
RHEL run `sudo setenforce 0` for the demo.

**`docker` needs sudo.** `bootstrap.sh` added `ec2-user` to the `docker` group,
which takes effect at next login. Reconnect, or keep using `sudo`.

**Everything is slow and questions time out.** Check free memory with `free -m`. If
you launched a `t3.medium` and you are on a multi-node question, that is the cause.
No need to rebuild: stop the instance, **Actions**, **Instance settings**,
**Change instance type**, pick `t3.large`, start it again. The disk, the images,
and the deployed code all survive.

**Builds fail with "no space left on device".** The root volume is too small.
Check with `df -h /`. Grow it without recreating anything: in the console, the
instance's **Storage** tab, click the volume, **Actions**, **Modify volume**, set
30 GiB, **Modify**. Then on the box, extend the partition and the filesystem:

```bash
[ec2-user@ip-10-0-0-1 ~]$ sudo growpart /dev/nvme0n1 1
[ec2-user@ip-10-0-0-1 ~]$ sudo xfs_growfs -d /
[ec2-user@ip-10-0-0-1 ~]$ df -h /
```

**You launched without a key pair.** There is no recovery path worth the effort.
Terminate the instance and repeat step 2. Nothing is lost, since the deploy has
not happened yet.
