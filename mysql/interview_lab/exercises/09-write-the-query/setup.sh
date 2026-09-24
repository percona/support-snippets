#!/bin/bash
# Nothing to break: employees is already in the datadir. This question is
# about composing a query, not repairing anything. All setup does is create
# the file the answer goes in.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true

install -m 644 -o candidate -g candidate /dev/null /home/candidate/answer.sql 2>/dev/null || true
