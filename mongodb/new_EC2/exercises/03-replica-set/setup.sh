#!/bin/bash
# node1 / node2: standalone mongod, no replication block — candidate adds
# replSetName, restarts, then initiates.
# node3: a "freshly provisioned host" — PSMDB is uninstalled here so the
# candidate must install it live from the (already configured) Percona repo
# before joining it to the set.
set -e

NODE="${NODE_NAME:-$(hostname)}"

if [ "$NODE" = "node3" ]; then
    systemctl stop mongod 2>/dev/null || true
    systemctl disable mongod 2>/dev/null || true

    # Preserve the canonical config (bindIp 0.0.0.0) so that once the
    # candidate reinstalls, node3 starts from the same baseline as node1/
    # node2 — only replSetName is left for them to add. PSMDB ships
    # mongod.conf as %config(noreplace), so a fresh `dnf install` keeps
    # this file and drops its default at mongod.conf.rpmnew.
    cp -a /etc/mongod.conf /opt/mongod.conf.canonical 2>/dev/null || true

    dnf -y remove 'percona-server-mongodb*' >/dev/null 2>&1 || true

    install -m 644 -o root -g root /opt/mongod.conf.canonical /etc/mongod.conf 2>/dev/null || true
    rm -f /etc/mongod.conf.rpmsave /etc/mongod.conf.rpmnew 2>/dev/null || true

    # Ensure the repo is enabled so `dnf install percona-server-mongodb`
    # works for the candidate without any repo setup of their own.
    percona-release enable psmdb-70 >/dev/null 2>&1 || true
    exit 0
fi

systemctl is-active mongod >/dev/null || systemctl start mongod || true
