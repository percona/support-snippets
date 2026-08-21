#!/bin/bash
# Initial state: standalone mongod is up. A customer-supplied FTDC chunk
# is staged at /opt/customer-ftdc/metrics.bson — its buildInfo.version
# is intentionally DIFFERENT from the live mongod's version, so the
# candidate cannot just `mongosh` the local server to get the answer;
# they must parse the customer file.
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

mkdir -p /opt/customer-ftdc
install -m 644 -o root -g root /opt/customer-metrics.bson \
    /opt/customer-ftdc/metrics.bson

# Make sure the answer file slot is writable by candidate.
install -m 644 -o candidate -g candidate /dev/null /home/candidate/answer.txt 2>/dev/null || true
