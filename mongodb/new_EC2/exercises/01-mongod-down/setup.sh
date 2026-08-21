#!/bin/bash
# Break mongod so the candidate sees a real "connection refused":
# point bindIp at an IP that doesn't exist on this host; mongod's listener
# will fail to bind and the service will exit non-zero.
set -e

systemctl stop mongod 2>/dev/null || true
sed -i 's/^[[:space:]]*bindIp:.*/  bindIp: 10.10.10.10/' /etc/mongod.conf

# Kick the service so the candidate sees an immediate "failed" state in
# `systemctl status mongod` rather than "inactive (dead)".
systemctl restart mongod 2>/dev/null || true

# Make the answer-file slot writable by the candidate (task 2: connection count).
install -m 644 -o candidate -g candidate /dev/null /home/candidate/answer.txt 2>/dev/null || true
