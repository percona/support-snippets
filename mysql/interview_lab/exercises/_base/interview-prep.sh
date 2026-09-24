#!/bin/bash
# Runs at boot BEFORE mysqld. Pulls the lab env vars out of PID 1 (docker -e),
# persists them for login shells and other units, and writes the per-node
# server_id so the three containers never collide on the same id.
set -e

while IFS= read -r -d '' kv; do
    case "$kv" in
        LEVEL=*|NODE_NAME=*|NODE_INDEX=*|NODE_PEERS=*|HISTDIR=*) export "$kv" ;;
    esac
done < /proc/1/environ

NODE_NAME="${NODE_NAME:-$(hostname)}"
NODE_INDEX="${NODE_INDEX:-0}"

mkdir -p /etc/sysconfig
{
    echo "LEVEL=${LEVEL:-0}"
    echo "NODE_NAME=${NODE_NAME}"
    echo "NODE_INDEX=${NODE_INDEX}"
    echo "NODE_PEERS=${NODE_PEERS:-$NODE_NAME}"
    # HISTDIR is the per-run transcript directory and only the controller sets
    # it. ttyd.service loads this file, which is how candidate-shell sees it.
    # Written only when present: an older controller or the smoke test leaves
    # it unset, and candidate-shell then falls back to the per-level path.
    if [ -n "${HISTDIR:-}" ]; then
        echo "HISTDIR=${HISTDIR}"
    fi
} > /etc/sysconfig/interview
chmod 644 /etc/sysconfig/interview

mkdir -p /etc/profile.d
{
    echo "export LEVEL=${LEVEL:-0}"
    echo "export NODE_NAME=${NODE_NAME}"
    echo "export NODE_INDEX=${NODE_INDEX}"
    echo "export NODE_PEERS=${NODE_PEERS:-$NODE_NAME}"
} > /etc/profile.d/interview.sh
chmod 644 /etc/profile.d/interview.sh

# server_id must be unique per node and must exist before mysqld starts.
mkdir -p /etc/my.cnf.d
cat > /etc/my.cnf.d/99-node.cnf <<NODECNF
[mysqld]
server_id   = $(( NODE_INDEX + 1 ))
report_host = ${NODE_NAME}
NODECNF
chmod 644 /etc/my.cnf.d/99-node.cnf

mkdir -p /var/run/mysqld /var/log/mysql
chown mysql:mysql /var/run/mysqld /var/log/mysql
