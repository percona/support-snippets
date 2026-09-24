#!/bin/bash
# Runs once at boot, after mysqld is up. Creates the lab-wide accounts, then
# invokes the per-question setup hook and DELETES it.
#
# Deleting /opt/setup.sh matters: the candidate has passwordless sudo (they
# need it to drive systemctl and edit my.cnf), so a setup.sh left on disk is
# readable with `sudo cat` and hands them the answer. Backgrounded work inside
# setup.sh keeps running after the file is gone.
set -e

# set -a so these reach setup.sh's environment. Sourcing alone defines them
# in this shell only, and setup.sh runs as a child process — without the
# export, NODE_INDEX is unset there and every node thinks it is node 0.
set -a
. /etc/sysconfig/interview 2>/dev/null || true
set +a

for _ in $(seq 1 120); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done

# Lab accounts: no passwords anywhere, matching the "no auth" shape of the lab.
# root@'%' lets the candidate reach the other nodes with `mysql -h node2`.
mysql --protocol=socket -uroot <<'SQL' >/dev/null 2>&1 || true
SET sql_log_bin = 0;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY 'repl';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'%';
-- The candidate's OS user needs a matching MySQL account, otherwise a plain
-- `mysql` (which defaults to the OS username) is denied and they have to
-- remember -uroot every time — friction that measures nothing.
CREATE USER IF NOT EXISTS 'candidate'@'localhost' IDENTIFIED WITH caching_sha2_password BY '';
CREATE USER IF NOT EXISTS 'candidate'@'%'         IDENTIFIED WITH caching_sha2_password BY '';
GRANT ALL PRIVILEGES ON *.* TO 'candidate'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'candidate'@'%'         WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

if [ -x /opt/setup.sh ]; then
    /opt/setup.sh || echo "setup.sh exited non-zero (continuing)"
fi

# Close the answer-key hole (see the comment at the top of this file).
rm -f /opt/setup.sh
