#!/bin/bash
# Runs once at boot via systemd. Pulls lab env vars from PID 1 (docker -e),
# persists them for login shells and other services, then invokes the
# per-level setup hook.
set -e

while IFS= read -r -d '' kv; do
    case "$kv" in
        LEVEL=*|NODE_NAME=*|NODE_INDEX=*|NODE_PEERS=*) export "$kv" ;;
    esac
done < /proc/1/environ

mkdir -p /etc/sysconfig
{
    echo "LEVEL=${LEVEL:-0}"
    echo "NODE_NAME=${NODE_NAME:-$(hostname)}"
    echo "NODE_INDEX=${NODE_INDEX:-0}"
    echo "NODE_PEERS=${NODE_PEERS:-$(hostname)}"
} > /etc/sysconfig/interview
chmod 644 /etc/sysconfig/interview

mkdir -p /etc/profile.d
{
    echo "export LEVEL=${LEVEL:-0}"
    echo "export NODE_NAME=${NODE_NAME:-$(hostname)}"
    echo "export NODE_INDEX=${NODE_INDEX:-0}"
    echo "export NODE_PEERS=${NODE_PEERS:-$(hostname)}"
} > /etc/profile.d/interview.sh
chmod 644 /etc/profile.d/interview.sh

# Wait for mongod to accept connections before per-level setup runs.
for _ in $(seq 1 90); do
    if mongosh --quiet --eval 'db.runCommand({ping:1}).ok' \
        mongodb://127.0.0.1:27017/admin >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -x /opt/setup.sh ]; then
    /opt/setup.sh || echo "setup.sh exited non-zero (continuing)"
fi
