#!/usr/bin/env bash
# Build a MySQL interview lab end to end: create the EC2 instance, deploy the
# lab onto it, and print the URLs. Optionally verify it.
#
#   ./launch-lab.sh                  create + deploy
#   ./launch-lab.sh --smoketest      create + deploy + verify: all 11 questions,
#                                    the negative cases, the security checks, and
#                                    the candidate page in a browser (needs node)
#   ./launch-lab.sh --help           this text
#
# Safe to re-run. It reuses the key pair and the security group if they already
# exist, and it will not launch a second instance under the same Name tag: when
# one exists (pending, running, stopping or stopped) it prints how to finish
# deploying that one or destroy it, and exits. FORCE_NEW=1 launches anyway.
#
# Environment overrides:
#   AWS_PROFILE   AWS CLI profile          (default: your AWS CLI default profile)
#   AWS_REGION    region                   (default: us-east-1)
#   NAME          instance Name tag        (default: mysql-interview-lab[-$LAB])
#   SGNAME        security group name      (default: mysql-interview-lab[-$LAB])
#   TYPE          instance type            (default: t3.large)
#   DISK          root volume GB           (default: 30)
#   AMI           image id                 (default: latest Amazon Linux 2023 x86_64)
#   KEYNAME       EC2 key pair name        (default: percona-interview-lab)
#   KEYFILE       local private key path   (default: ~/.ssh/percona-interview-lab.pem)
#   CREATE_KEY=1  create the key pair if it is missing from EC2
#   LAB           name a parallel lab, e.g. LAB=ana: its own instance + security group
#   OPEN_HTTP     CIDR to allow on port 80 besides your own IP (default: none)
#   CAND_PASS     candidate basic-auth password    (else prompted at the start)
#   INTV_PASS     interviewer basic-auth password  (else prompted at the start)
#   FORCE_NEW=1   launch even though a lab with this NAME already exists
#   NO_DEPLOY=1   create the instance and stop, without deploying the lab
#   LOGFILE       where to write the run log (default: $TMPDIR/interview-lab-<ts>.log)
set -euo pipefail

# Everything this script and the deploy it calls print goes to a log as well as
# to the screen. A build is ~15 minutes of mostly unattended output, and when
# something fails at minute 28 the scrollback is the only evidence of why.
SMOKETEST=0
for a in "$@"; do
    case "$a" in
        --smoketest|--run-smoketest|-s) SMOKETEST=1 ;;
        # The whole header comment, however long it grows: a fixed line
        # range silently cut off everything added below it.
        -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 1 ;;
    esac
done

# The lab name is in it: two launches started in the same second would
# otherwise share one file.
LOGFILE="${LOGFILE:-${TMPDIR:-/tmp}/interview-lab-${LAB:-default}-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1
echo "==> log: $LOGFILE"

# Both passwords are collected HERE, not left to deploy.sh. deploy.sh prompts in
# a child shell, so its answers never reach this script — and with --smoketest
# that means a second, hidden prompt appears 33 minutes in, on a run the user
# has walked away from, and waits forever.
WEAK_PASS=0
for v in CAND_PASS INTV_PASS; do
    eval "cur=\${$v:-}"
    if [ -z "$cur" ]; then
        # -r /dev/tty is true on macOS even with no controlling terminal;
        # opening it is the only reliable test. Same idiom as remote-smoketest.sh.
        if ! { : </dev/tty; } 2>/dev/null; then
            echo "error: $v is not set and there is no terminal to ask on." >&2
            echo "  run with: CAND_PASS=... INTV_PASS=... $0" >&2
            exit 1
        fi
        case "$v" in
            CAND_PASS) read -rsp "candidate password   : " cur </dev/tty ;;
            INTV_PASS) read -rsp "interviewer password : " cur </dev/tty ;;
        esac
        echo
    fi
    # gen-auth.sh will happily hash an empty string, which leaves the lab open
    # to every allowed IP with a blank password.
    [ -n "$cur" ] || { echo "error: $v must not be empty." >&2; exit 1; }
    [ "${#cur}" -ge 10 ] || WEAK_PASS=1
    eval "$v=\$cur"
done
export CAND_PASS INTV_PASS

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-us-east-1}"
# LAB namespaces a parallel lab: LAB=ana gives its own instance name AND its own
# security group, so opening port 80 for one candidate cannot expose another
# candidate's box. Unset, everything keeps the plain names.
LAB="${LAB:-}"
NAME="${NAME:-mysql-interview-lab${LAB:+-$LAB}}"
TYPE="${TYPE:-t3.large}"
DISK="${DISK:-30}"
KEYNAME="${KEYNAME:-percona-interview-lab}"
KEYFILE="${KEYFILE:-$HOME/.ssh/percona-interview-lab.pem}"
SGNAME="${SGNAME:-mysql-interview-lab${LAB:+-$LAB}}"

aws() {
    if [ -n "$PROFILE" ]; then command aws --profile "$PROFILE" --region "$REGION" "$@"
    else command aws --region "$REGION" "$@"; fi
}

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "error: no valid credentials for profile '${PROFILE:-<default>}'." >&2
    echo "  log in first:  aws sso login${PROFILE:+ --profile $PROFILE}" >&2
    exit 1
fi

MYIP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
echo "==> your public IP: $MYIP  (SSH will be restricted to it)"

echo "==> resolving the latest Amazon Linux 2023 AMI"
# Resolved with ec2:DescribeImages rather than ssm:GetParameter — some SSO
# roles (the Percona sandbox engineer role among them) are not granted
# ssm:GetParameter, and the SSM lookup fails the whole script.
AMI="${AMI:-$(aws ec2 describe-images --owners amazon \
  --filters 'Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64' \
            'Name=state,Values=available' 'Name=architecture,Values=x86_64' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)}"
echo "    $AMI"

echo "==> key pair '$KEYNAME'"
if aws ec2 describe-key-pairs --key-names "$KEYNAME" >/dev/null 2>&1; then
    echo "    exists in EC2"
    [ -f "$KEYFILE" ] || { echo "    error: $KEYFILE is missing locally, and AWS will not re-issue it." >&2
                           echo "    Delete the EC2 key pair and re-run with CREATE_KEY=1 KEYNAME=<new-name>." >&2
                           exit 2; }
elif [ "${CREATE_KEY:-0}" = 1 ]; then
    [ -e "$KEYFILE" ] && { echo "    refusing to overwrite existing $KEYFILE" >&2; exit 2; }
    aws ec2 create-key-pair --key-name "$KEYNAME" \
        --query KeyMaterial --output text > "$KEYFILE"
    chmod 400 "$KEYFILE"
    echo "    created, private key saved to $KEYFILE"
else
    echo "    error: key pair '$KEYNAME' does not exist in EC2." >&2
    echo "    Re-run with CREATE_KEY=1 to create it (writes $KEYFILE)." >&2
    exit 2
fi

echo "==> security group '$SGNAME'"
SG="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SGNAME" \
      --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo None)"
if [ "$SG" = "None" ] || [ -z "$SG" ]; then
    VPC="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
           --query 'Vpcs[0].VpcId' --output text)"
    [ "$VPC" = "None" ] && { echo "    error: no default VPC in $REGION. Create one, or pass an existing SG." >&2; exit 1; }
    SG="$(aws ec2 create-security-group --group-name "$SGNAME" \
          --description "Support Engineer interview lab: HTTP + SSH" \
          --vpc-id "$VPC" --query GroupId --output text)"
    echo "    created $SG in $VPC"
else
    echo "    exists: $SG"
fi

# SSH from your IP only.
if aws ec2 authorize-security-group-ingress --group-id "$SG" \
      --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$MYIP/32,Description=deployer}]" \
      >/dev/null 2>&1; then
    echo "    added SSH from $MYIP/32"
else
    echo "    SSH rule for $MYIP/32 already present"
fi

# Port 80 is opened to whoever ran this, and to nobody else. You need it to see
# the dashboard and to verify the lab at all, so it is not worth making opt-in.
# Everyone else goes in one at a time with tools/allow-ip.sh: this is plain HTTP
# behind a basic-auth password, and opening it to the world in a shared account
# is how it gets found.
if aws ec2 authorize-security-group-ingress --group-id "$SG" \
      --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=$MYIP/32,Description=interviewer}]" \
      >/dev/null 2>&1; then
    echo "    added HTTP from $MYIP/32 (you)"
else
    echo "    HTTP rule for $MYIP/32 already present"
fi
if [ -n "${OPEN_HTTP:-}" ]; then
    aws ec2 authorize-security-group-ingress --group-id "$SG" \
        --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=$OPEN_HTTP,Description=lab-viewer}]" \
        >/dev/null 2>&1 && echo "    added HTTP from $OPEN_HTTP" || echo "    HTTP rule for $OPEN_HTTP already present"
fi

# A retry after any later failure would otherwise launch a SECOND t3.large with
# the same name, both billing, and a later destroy would kill both. Almost every
# reason to re-run this is "the deploy failed", which needs deploy.sh, not a new
# machine.
EXISTING="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$NAME" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' \
    --output text)"
if [ -n "$EXISTING" ] && [ "${FORCE_NEW:-0}" != 1 ]; then
    echo "==> a lab named '$NAME' already exists:"
    echo "$EXISTING" | sed 's/^/    /'
    cat >&2 <<EOF

Not launching another — you would pay for both.
  finish deploying it : ./deploy.sh ec2-user@<its ip> -i $KEYFILE
  throw it away       : ${LAB:+LAB=$LAB }./tools/destroy-lab.sh
  really want a second: FORCE_NEW=1 ${LAB:+LAB=$LAB }$0
EOF
    exit 1
fi

echo "==> launching $TYPE with a ${DISK}GB gp3 root volume"
IID="$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEYNAME" \
    --security-group-ids "$SG" \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=$DISK,VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options "HttpTokens=required" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Purpose,Value=mysql-support-engineer-interview-lab}]" \
    --query 'Instances[0].InstanceId' --output text)"
echo "    $IID"

# From here on the instance is billing. Every exit path that is not a success
# has to say so, with the two commands that resolve it — otherwise a failure at
# minute 30 leaves a t3.large running that nobody remembers.
orphan_notice() {
    local rc=$?
    [ "$rc" = 0 ] && return 0
    cat >&2 <<EOF

==> instance $IID IS STILL RUNNING and billing${IP:+ (}${IP:-}${IP:+)}
    resume the deploy : ./deploy.sh ec2-user@${IP:-<ip>} -i $KEYFILE
    throw it away     : ${LAB:+LAB=$LAB }./tools/destroy-lab.sh
    log               : $LOGFILE
EOF
    return "$rc"
}
trap orphan_notice EXIT

echo "==> waiting for status checks to pass (2-3 minutes)"
aws ec2 wait instance-status-ok --instance-ids "$IID"

IP="$(aws ec2 describe-instances --instance-ids "$IID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
if [ "$IP" = "None" ] || [ -z "$IP" ]; then
    echo "error: the instance has no public IP — the subnet does not auto-assign one." >&2
    exit 1
fi
# A recycled EC2 address with a different host key makes every ssh attempt fail
# with a host-key error that reads like a permissions problem.
ssh-keygen -R "$IP" >/dev/null 2>&1 || true

cat <<EOF

==> instance is up
    name : $NAME
    id   : $IID
    ip   : $IP   (changes on every stop/start, there is no Elastic IP)
    sg   : $SG
EOF

# A bare instance is of no use to anybody, so this keeps going into the deploy
# by default: one command from nothing to a lab you can hand to a candidate.
# NO_DEPLOY=1 stops here, for the rare case of wanting the box on its own.
if [ "${NO_DEPLOY:-0}" = 1 ]; then
    cat <<EOF

Next, from the project root:
    ./deploy.sh ec2-user@$IP -i $KEYFILE
EOF
    exit 0
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"

# `wait instance-status-ok` says the hypervisor is happy; it says nothing about
# sshd being up and accepting this key. Deploying a second too early fails on a
# connection refused that looks like a permissions problem.
echo "==> waiting for SSH on $IP"
ssh_up=0
for _ in $(seq 1 40); do
    if ssh -i "$KEYFILE" -o StrictHostKeyChecking=accept-new \
           -o ConnectTimeout=5 -o BatchMode=yes "ec2-user@$IP" true 2>/dev/null; then
        ssh_up=1; break
    fi
    sleep 5
done
if [ "$ssh_up" != 1 ]; then
    echo "error: no SSH on $IP after 200s. The instance is up; check the security group." >&2
    echo "  then: ./deploy.sh ec2-user@$IP -i $KEYFILE" >&2
    exit 1
fi

echo "==> deploying the lab (about 15 minutes: upload, then the image build)"
if ! "$ROOT/deploy.sh" "ec2-user@$IP" -i "$KEYFILE"; then
    cat >&2 <<EOF

==> deploy failed. The instance is up and reachable, so fix the cause and
    re-run just the deploy — you do not need a new machine:
        ./deploy.sh ec2-user@$IP -i $KEYFILE
    Full log: $LOGFILE
EOF
    exit 1
fi

# Verifying is the whole point of the flag, so a failure here has to be loud and
# has to make the script exit non-zero: a lab that builds but fails a question,
# a NEG case or a SEC assertion is not a lab you can interview on.
SMOKE_RESULT="not run"
if [ "$SMOKETEST" = 1 ]; then
    echo
    echo "==> verifying the lab (about 10 minutes): 11 questions, negative cases, security"
    # CAND_PASS is the candidate password, which is exactly what the paste-guard
    # assertion needs; without it that one check reports SKIPPED.
    if LAB_PASS="${CAND_PASS:-}" "$ROOT/tools/remote-smoketest.sh" \
           "ec2-user@$IP" -i "$KEYFILE"; then
        SMOKE_RESULT="passed"
    else
        SMOKE_RESULT="FAILED"
    fi

    # The suite proves the graders; only a browser proves the page a candidate
    # presses Send on. A laptop without node or the cached Chromium skips it and
    # says so, rather than failing a lab that is fine.
    if [ "$SMOKE_RESULT" = passed ]; then
        echo
        echo "==> verifying the candidate page in a browser (about 2 minutes)"
        rc=0
        if ! command -v node >/dev/null 2>&1; then
            rc=3; echo "node is not installed (brew install node)"
        else
            "$ROOT/tools/browser-test.sh" "ec2-user@$IP" -i "$KEYFILE" || rc=$?
        fi
        case "$rc" in
            0) SMOKE_RESULT="passed (suite + browser)" ;;
            3) SMOKE_RESULT="passed (suite only; browser test skipped, see above)" ;;
            *) SMOKE_RESULT="FAILED" ;;
        esac
    fi
fi

cat <<EOF

==> the lab is ready${LAB:+: LAB=$LAB}
    candidate   http://$IP/
    interviewer http://$IP/interviewer/
    ssh         ssh -i $KEYFILE ec2-user@$IP
    instance    $IID     sg $SG

    verified    $SMOKE_RESULT

Full log of this run: $LOGFILE
    (it names every question and the wrong fixes the suite tries: never share it with a candidate)

Port 80 is open to you only. Let a candidate in with:
    ${LAB:+LAB=$LAB }./tools/allow-ip.sh <THEIR_IP> candidate

Or by hand:
    aws ec2 authorize-security-group-ingress --group-id $SG \\
      --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=<THEIR_IPv4>/32}]"
EOF

# Not refused: short passwords are the norm on a throwaway test lab. The lab is
# plain HTTP behind an IP allow-list, so the password is the only other lock.
if [ "$WEAK_PASS" = 1 ]; then
    cat >&2 <<EOF

==> a password is under 10 characters. Fine for a test lab; before a real
    candidate, rotate both from here. They go over ssh on stdin, never onto the
    server's command line or shell history, which a candidate could read:
        printf '%s\n%s\n' '<candidate pw>' '<interviewer pw>' | \\
          ssh -i $KEYFILE ec2-user@$IP 'cd mysql-interview-lab && ./gen-auth.sh >/dev/null && docker compose restart nginx'
EOF
fi

if [ "$SMOKE_RESULT" = FAILED ]; then
    echo "==> DO NOT interview on this lab until the suite passes. Log: $LOGFILE" >&2
    exit 1
fi
if [ "$SMOKE_RESULT" = "not run" ]; then
    echo "Verify before you put anyone in front of it:"
    echo "    ./tools/remote-smoketest.sh ec2-user@$IP -i $KEYFILE"
fi
