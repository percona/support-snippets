#!/bin/bash
# Break mysqld so the candidate sees a real "can't connect": point
# bind-address at an IP that does not exist on this host. The listener fails
# to bind and the service exits non-zero.
#
# Second half of the question: the application really is close to its
# connection ceiling. max_connections is lowered to 50 and a pool of
# application connections is held open by webapp.service. Each worker
# reconnects on its own, so the pool rebuilds within a few seconds of the
# candidate restarting mysqld — otherwise it would be empty at exactly the
# moment they go to measure it. The pool size is randomised per boot inside
# webapp.sh so it cannot be read off disk; the candidate has to count it.
set -e

# The application account whose connections the candidate has to count.
mysql -uroot <<'SQL'
SET sql_log_bin = 0;
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH caching_sha2_password BY 'appuser';
GRANT USAGE ON *.* TO 'appuser'@'%';
SQL

# A ceiling low enough that the open pool is genuinely a concern.
cat > /etc/my.cnf.d/50-app.cnf <<'CNF'
[mysqld]
max_connections = 50
CNF
chmod 644 /etc/my.cnf.d/50-app.cnf

systemctl enable webapp.service >/dev/null 2>&1 || true
systemctl start  webapp.service >/dev/null 2>&1 || true

systemctl stop mysqld 2>/dev/null || true
sed -i 's/^bind-address.*/bind-address             = 10.10.10.10/' /etc/my.cnf

# Kick the service so the candidate sees an immediate "failed" state in
# `systemctl status mysqld` rather than "inactive (dead)".
systemctl restart mysqld 2>/dev/null || true

install -m 644 -o candidate -g candidate /dev/null /home/candidate/answer.txt 2>/dev/null || true
