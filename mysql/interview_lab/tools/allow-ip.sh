#!/usr/bin/env bash
# Let an address reach the lab, or take the access away again.
#
#   ./tools/allow-ip.sh 203.0.113.7 candidate     # allow on port 80
#   ./tools/allow-ip.sh 203.0.113.7 --revoke      # remove
#   ./tools/allow-ip.sh --me --port 22            # your current IP, SSH
#   ./tools/allow-ip.sh --list                    # who can reach it
#
#   LAB=ana ./tools/allow-ip.sh 203.0.113.7       # a named parallel lab
#
# A bare IPv4 gets /32 added for you. The lab is plain HTTP behind a basic-auth
# password, so access is granted one address at a time and never to 0.0.0.0/0.
set -euo pipefail

LAB="${LAB:-}"
SGNAME="${SGNAME:-mysql-interview-lab${LAB:+-$LAB}}"
REGION="${AWS_REGION:-us-east-1}"
PORT=80
CIDR=""
DESC="candidate"
REVOKE=0
ACTION=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --list)   ACTION=list ;;
        --revoke) REVOKE=1 ;;
        --port)   PORT="${2:?--port needs a number}"; shift ;;
        --me)     CIDR="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')/32"
                  # Your own access, so label it that way: a rule marked
                  # "candidate" is the one you revoke after an interview.
                  [ "$DESC" = candidate ] && DESC=interviewer ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 1 ;;
        *)  if [ -z "$CIDR" ]; then CIDR="$1"; else DESC="$1"; fi ;;
    esac
    shift
done

aws() { command aws --region "$REGION" ${AWS_PROFILE:+--profile "$AWS_PROFILE"} "$@"; }

if [ -z "$ACTION" ] && [ -z "$CIDR" ]; then sed -n '2,13p' "$0"; exit 1; fi

# Validate before calling AWS: a typo'd address otherwise becomes a rule that
# matches nothing, and the candidate is locked out with no error to show for it.
if [ -n "$CIDR" ]; then
    case "$CIDR" in */*) ;; *) CIDR="$CIDR/32" ;; esac
    if ! printf '%s' "$CIDR" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        echo "error: '$CIDR' is not an IPv4 address or CIDR." >&2
        echo "  The lab has no IPv6; an IPv6 address would be a rule that never matches." >&2
        exit 1
    fi
    if [ "$CIDR" = "0.0.0.0/0" ]; then
        echo "error: refusing to open the lab to the entire internet." >&2
        exit 1
    fi
fi

if ! SG="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SGNAME" \
           --query 'SecurityGroups[0].GroupId' --output text 2>&1)"; then
    echo "error: could not look up the security group: $SG" >&2
    exit 1
fi
if [ "$SG" = "None" ] || [ -z "$SG" ]; then
    echo "error: no security group named '$SGNAME'." >&2
    echo "  Wrong LAB=? Set SG=sg-... or SGNAME=... to override." >&2
    exit 1
fi

show() {
    echo "Allowed on $SG ($SGNAME):"
    aws ec2 describe-security-groups --group-ids "$SG" \
      --query 'SecurityGroups[0].IpPermissions[].{Port:FromPort,CIDR:IpRanges[0].CidrIp,Who:IpRanges[0].Description}' \
      --output table
}

[ "$ACTION" = list ] && { show; exit 0; }

# Only a duplicate/absent rule is benign. Everything else — expired token, no
# permission, malformed request — used to print "already allowed", which reads
# as success while the candidate cannot connect.
if [ "$REVOKE" = 1 ]; then
    if err="$(aws ec2 revoke-security-group-ingress --group-id "$SG" \
              --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,IpRanges=[{CidrIp=$CIDR}]" 2>&1)"; then
        echo "removed $CIDR on port $PORT"
    elif printf '%s' "$err" | grep -q 'InvalidPermission.NotFound'; then
        echo "no rule for $CIDR on port $PORT"
    else
        echo "error: could not revoke $CIDR: $err" >&2; exit 1
    fi
else
    if err="$(aws ec2 authorize-security-group-ingress --group-id "$SG" \
              --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,IpRanges=[{CidrIp=$CIDR,Description=$DESC}]" 2>&1)"; then
        echo "allowed $CIDR on port $PORT ($DESC)"
    elif printf '%s' "$err" | grep -q 'InvalidPermission.Duplicate'; then
        echo "$CIDR already allowed on port $PORT"
    else
        echo "error: could not allow $CIDR: $err" >&2; exit 1
    fi
fi
echo
show
