#!/bin/bash
# node1 / node2: mysqld running, nothing replicating — the candidate wires
# them together.
# node3: the Percona Server packages are uninstalled here, so the candidate
# must install them live from the (already configured) Percona repo before
# joining it to the topology. Only the packages go: /etc/my.cnf and the whole
# datadir stay on disk, and the README says so — an earlier wording called
# node3 "freshly provisioned", which sent candidates off to clone node1's
# data for no reason.
set -e

NODE="${NODE_NAME:-$(hostname)}"

if [ "$NODE" = "node3" ]; then
    systemctl stop mysqld 2>/dev/null || true
    systemctl disable mysqld 2>/dev/null || true

    # Preserve the canonical config so that once the candidate reinstalls,
    # node3 starts from the same baseline as node1/node2. The RPM ships
    # my.cnf as a config file, so a fresh install keeps this one and drops
    # its default alongside as my.cnf.rpmnew.
    cp -a /etc/my.cnf /opt/my.cnf.canonical 2>/dev/null || true

    # --noautoremove matters: without it dnf also tears out the shared
    # libraries, ICU data and perl modules that came in as dependencies, and
    # the candidate's reinstall then has to pull ~32 packages over the
    # network. Removing only the server and client keeps the reinstall
    # satisfiable from the locally staged repo, in seconds.
    dnf -y remove --noautoremove 'percona-server-server*' 'percona-server-client*' >/dev/null 2>&1 || true

    install -m 644 -o root -g root /opt/my.cnf.canonical /etc/my.cnf 2>/dev/null || true
    rm -f /etc/my.cnf.rpmsave /etc/my.cnf.rpmnew 2>/dev/null || true

    # Make sure the repo is enabled so `dnf install percona-server-server`
    # works for the candidate without any repo setup of their own.
    percona-release enable ps-80 release >/dev/null 2>&1 || true
    exit 0
fi

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true
