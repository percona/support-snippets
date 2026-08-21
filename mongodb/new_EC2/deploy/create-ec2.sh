#!/usr/bin/env bash
# Create the EC2 instance that hosts the interview lab, then print the
# deploy.sh command to run against it.
#
#   ./deploy/create-ec2.sh
#
# Idempotent in the parts that matter: it reuses the key pair and the security
# group if they already exist. It always launches a NEW instance, so check for
# a running one first (see EC2-SETUP.md, step 1).
#
# Environment overrides:
#   AWS_PROFILE   AWS CLI profile          (default: your AWS CLI default profile)
#   AWS_REGION    region                   (default: us-east-1)
#   NAME          instance Name tag        (default: dba-interview-lab)
#   TYPE          instance type            (default: t3.large)
#   DISK          root volume GB           (default: 30)
#   KEYNAME       EC2 key pair name        (default: dba-interview-lab)
#   KEYFILE       local private key path   (default: ~/.ssh/dba-interview-lab.pem)
#   CREATE_KEY=1  create the key pair if it is missing from EC2
#   OPEN_HTTP     CIDR to allow on port 80 (default: none, add it at demo time)
set -euo pipefail

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-us-east-1}"
NAME="${NAME:-dba-interview-lab}"
TYPE="${TYPE:-t3.large}"
DISK="${DISK:-30}"
KEYNAME="${KEYNAME:-dba-interview-lab}"
KEYFILE="${KEYFILE:-$HOME/.ssh/dba-interview-lab.pem}"
SGNAME="${SGNAME:-dba-interview-lab}"

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
AMI="$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)"
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

# Port 80 is opt-in, per viewer. Leaving it open in a shared account is how a
# plain-HTTP basic-auth box gets found.
if [ -n "${OPEN_HTTP:-}" ]; then
    aws ec2 authorize-security-group-ingress --group-id "$SG" \
        --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=$OPEN_HTTP,Description=lab-viewer}]" \
        >/dev/null 2>&1 && echo "    added HTTP from $OPEN_HTTP" || echo "    HTTP rule for $OPEN_HTTP already present"
else
    echo "    port 80 not opened (set OPEN_HTTP=<cidr>, or add it at demo time)"
fi

echo "==> launching $TYPE with a ${DISK}GB gp3 root volume"
IID="$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEYNAME" \
    --security-group-ids "$SG" \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=$DISK,VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options "HttpTokens=required" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Purpose,Value=support-engineer-interview-lab}]" \
    --query 'Instances[0].InstanceId' --output text)"
echo "    $IID"

echo "==> waiting for status checks to pass (about 60s)"
aws ec2 wait instance-status-ok --instance-ids "$IID"

IP="$(aws ec2 describe-instances --instance-ids "$IID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"

cat <<EOF

==> instance is up
    name : $NAME
    id   : $IID
    ip   : $IP   (changes on every stop/start, there is no Elastic IP)
    sg   : $SG

Next, from the project root:
    ./deploy.sh ec2-user@$IP -i $KEYFILE

Then verify:
    ssh -i $KEYFILE ec2-user@$IP 'cd dba-interview-lab && ./smoketest.sh 1 2'
EOF
