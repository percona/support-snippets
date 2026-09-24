#!/usr/bin/env bash
# Terminate a lab instance. Shows what will go, then asks.
#
#   ./tools/destroy-lab.sh              # the default lab
#   ./tools/destroy-lab.sh -y=mysql-interview-lab   # no prompt; must name the lab
#   LAB=ana ./tools/destroy-lab.sh      # a named parallel lab
#   ./tools/destroy-lab.sh --keep-sg    # leave the security group behind
#
# Termination is irreversible and takes the root volume with it: the images,
# the transcripts and any candidate evidence on that box are gone. Export
# anything you need first (see RUNBOOK, "Between candidates").
#
# The security group goes too. Left behind it accumulates a rule per candidate,
# and an ex-candidate's IP still allowed months later can reach whatever lab is
# running on that group. launch-lab.sh recreates it and re-adds your own SSH and
# HTTP rules, so the only thing you lose is stale access you did not want.
# --keep-sg opts out, for when you are rebuilding straight away and do not want
# to re-add a candidate's address.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
LAB="${LAB:-}"
NAME="${NAME:-mysql-interview-lab${LAB:+-$LAB}}"
SGNAME="${SGNAME:-mysql-interview-lab${LAB:+-$LAB}}"
YES=""; DROP_SG=1; ALL=0
for a in "$@"; do
    case "$a" in
        -y=*|--yes=*) YES="${a#*=}" ;;
        --all) ALL=1 ;;
        --keep-sg) DROP_SG=0 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 1 ;;
    esac
done

aws() { command aws --region "$REGION" ${AWS_PROFILE:+--profile "$AWS_PROFILE"} "$@"; }

IDS="$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$NAME" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text)"

if [ -z "$IDS" ]; then
    echo "no instance named '$NAME' is alive"
else
    COUNT="$(printf '%s\n' $IDS | wc -w | tr -d ' ')"
    # More than one instance carries this name. In a shared sandbox that is
    # usually a colleague's lab, or a half-launched one — not something to
    # terminate on a single confirmation aimed at a name.
    if [ "$COUNT" -gt 1 ] && [ "$ALL" != 1 ]; then
        echo "error: $COUNT instances are named '$NAME'. Refusing to terminate them all." >&2
        aws ec2 describe-instances --instance-ids $IDS \
          --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Launched:LaunchTime}' \
          --output table >&2
        echo "  terminate one : aws ec2 terminate-instances --instance-ids <id>" >&2
        echo "  all of them   : $0 --all" >&2
        exit 1
    fi

    echo "About to TERMINATE (irreversible, root volume goes too):"
    aws ec2 describe-instances --instance-ids $IDS \
      --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,IP:PublicIpAddress}' \
      --output table
    echo "The root volume goes with it: images, transcripts and any candidate"
    echo "evidence on that box. Export first if you need it (RUNBOOK, After)."
    # -y must name the lab. A bare -y plus a forgotten or stale LAB= export is
    # how you silently terminate a different lab than the one you meant.
    if [ -n "$YES" ]; then
        [ "$YES" = "$NAME" ] || {
            echo "error: -y=$YES does not match the lab being destroyed ($NAME)." >&2; exit 1; }
    else
        printf 'Type the lab name (%s) to confirm: ' "$NAME"
        read -r reply
        [ "$reply" = "$NAME" ] || { echo "aborted"; exit 1; }
    fi
    aws ec2 terminate-instances --instance-ids $IDS >/dev/null
    echo "terminating; waiting..."
    aws ec2 wait instance-terminated --instance-ids $IDS
    echo "terminated"
fi

if [ "$DROP_SG" = 1 ]; then
    SG="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SGNAME" \
          --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo None)"
    if [ "$SG" = "None" ] || [ -z "$SG" ]; then
        echo "no security group named '$SGNAME'"
    else
        # A group still attached to a dying instance cannot be deleted; the wait
        # above means the ENI is usually gone, but AWS can lag a few seconds.
        err=""
        deleted=0
        for _ in $(seq 1 12); do
            if err="$(aws ec2 delete-security-group --group-id "$SG" 2>&1)"; then
                echo "deleted security group $SG ($SGNAME)"; deleted=1; break
            fi
            sleep 5
        done
        # Exiting 0 here would report a clean teardown while leaving a group full
        # of ex-candidates' addresses behind, which is exactly what deleting it
        # by default is meant to prevent.
        if [ "$deleted" != 1 ]; then
            echo "error: could not delete security group $SG ($SGNAME):" >&2
            echo "  ${err:-unknown error}" >&2
            exit 1
        fi
    fi
fi
