#!/bin/bash
# Initial state: a healthy 3-node topology, then node3 is placed under the kind
# of instance-wide read lock a backup routine leaves behind when it is
# interrupted mid-run. While the lock is held node3's SQL applier cannot
# commit, so it falls further behind while node1 keeps taking writes.
#
# The lock is held by a small systemd service rather than a one-shot client on
# purpose. A one-shot client dies when mysqld is bounced, so a blind
# `systemctl restart mysqld` would clear the condition as a side effect and the
# question could be "passed" with no diagnosis at all — which is the whole
# point of this level. The service re-acquires the lock after the server is
# restarted, so a restart no longer resolves anything; ending the offending
# session (or stopping the service that owns it) is what resolves it. It does
# not fight back once its own session is gone on a server that is still up, so
# a correct fix finishes the question cleanly.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true

/usr/local/sbin/repl-bootstrap

if [ "${NODE_NAME:-$(hostname)}" = "node3" ]; then
    # The lock holder is installed as a service with a neutral name, so that
    # merely listing units does not reveal what it does: the candidate has to
    # look at the server's own state to find it. root-only (0700), since it is
    # infrastructure the candidate does not need to read to solve the question.
    cat > /usr/local/sbin/db-snapshot <<'HELPER'
#!/bin/bash
# Periodic database snapshot helper. Takes an instance-wide read lock so the
# on-disk files are consistent for the snapshot window, holds it, then releases
# it. The lock is connection-scoped, so it ends the instant this session ends.
#
# If the server is restarted the helper reconnects and takes the lock again for
# the next window; if an operator ends this session while the server stays up,
# the helper treats the window as finished and exits for good. It tells the two
# apart by the server's PID: a killed session leaves the same mysqld instance
# running, a restart brings up a new one.
sockping() { mysqladmin --protocol=socket ping >/dev/null 2>&1; }
pidnow()   { cat /var/run/mysqld/mysqld.pid 2>/dev/null; }

first=1
while true; do
    for _ in $(seq 1 240); do sockping && break; sleep 1; done
    sockping || { sleep 2; continue; }

    # On the first window, wait until node3 is actually replicating so the lag
    # the lock produces is meaningful. On later windows (after a restart) take
    # the lock straight away, so a restart cannot buy a lag-free gap.
    if [ "$first" = 1 ]; then
        for _ in $(seq 1 120); do
            io=$(mysql -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null \
                 | awk -F': *' '/Replica_IO_Running:/{print $2; exit}' | tr -d '[:space:]')
            [ "$io" = "Yes" ] && break
            sleep 1
        done
        first=0
    fi

    inst=$(pidnow)
    mysql -uroot -e "FLUSH TABLES WITH READ LOCK; SELECT SLEEP(86400);" >/dev/null 2>&1

    # The session ended. Let a possible restart settle, then decide whether the
    # same server instance is still up (session was ended by an operator -> the
    # window is over, stop) or a new one is (server was restarted -> loop and
    # take the lock again).
    sleep 1
    for _ in $(seq 1 120); do sockping && break; sleep 1; done
    if sockping && [ -n "$inst" ] && [ "$(pidnow)" = "$inst" ]; then
        exit 0
    fi
done
HELPER
    chown root:root /usr/local/sbin/db-snapshot
    chmod 700 /usr/local/sbin/db-snapshot

    cat > /etc/systemd/system/db-snapshot.service <<'UNIT'
[Unit]
Description=Database snapshot
After=mysqld.service
Wants=mysqld.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/db-snapshot
# on-failure, not always: a clean stop (the operator finding and stopping this
# service) must not be undone, but a crash of the helper should recover.
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable --now db-snapshot.service >/dev/null 2>&1 || true
fi

if [ "${NODE_INDEX:-0}" = "0" ]; then
    # Stream writes on the source forever so the lag on node3 stays visible
    # until the candidate fixes it. Launched with `nohup bash -c` so the exec
    # drops the file descriptor this setup script is read from: a plain
    # backgrounded subshell inherits that descriptor and, because the loop
    # outlives the setup that deletes the script, lets the deleted file be
    # recovered from /proc/<pid>/fd — comments and all. An exec closes it.
    nohup bash -c '
        for _ in $(seq 1 120); do
            mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
            sleep 1
        done
        mysql -uroot -e "
          CREATE DATABASE IF NOT EXISTS app;
          CREATE TABLE IF NOT EXISTS app.events (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            t  DATETIME(3) NOT NULL,
            n  DOUBLE      NOT NULL
          ) ENGINE=InnoDB;" >/dev/null 2>&1
        while true; do
            mysql -uroot -e \
              "INSERT INTO app.events (t, n) VALUES (NOW(3), RAND());" >/dev/null 2>&1
            sleep 2
        done
    ' >/dev/null 2>&1 &
fi
