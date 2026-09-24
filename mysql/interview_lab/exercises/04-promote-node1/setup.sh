#!/bin/bash
# Initial state: healthy GTID replication, but with node2 as the source and
# node1 demoted to a read-only replica. The candidate performs a controlled
# failback to node1.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true

/usr/local/sbin/repl-bootstrap node2
