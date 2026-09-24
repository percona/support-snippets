#!/bin/bash
# employees is already in the datadir. Take a raw (unprepared) XtraBackup of
# the instance, leave it in /backups, then drop the database. The candidate
# has to --prepare the backup and put the data back, which is the procedure
# a Percona customer actually follows.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true

for _ in $(seq 1 120); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done

LOG=/var/log/repl-bootstrap.log
mkdir -p /backups
rm -rf /backups/full
xtrabackup --backup --target-dir=/backups/full \
    --user=root --socket=/var/lib/mysql/mysql.sock >>"$LOG" 2>&1

chown -R candidate:candidate /backups

mysql -uroot -e "DROP DATABASE employees;"
