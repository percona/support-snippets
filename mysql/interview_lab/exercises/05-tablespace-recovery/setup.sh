#!/bin/bash
# employees is already in the datadir (baked into the base image), so all
# this has to do is take the tablespace away from one table and leave the
# .ibd where the "storage team" put it. The documented route back is
# DISCARD (already done) -> put the file in place with the right ownership
# -> ALTER TABLE ... IMPORT TABLESPACE.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true
for _ in $(seq 1 120); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done

# Clean shutdown first, so the copied .ibd is consistent.
systemctl stop mysqld
for _ in $(seq 1 60); do
    systemctl is-active mysqld >/dev/null 2>&1 || break
    sleep 1
done

mkdir -p /opt/recovered
cp -a /var/lib/mysql/employees/titles.ibd /opt/recovered/titles.ibd
chown candidate:candidate /opt/recovered/titles.ibd
chmod 644 /opt/recovered/titles.ibd

systemctl start mysqld
for _ in $(seq 1 120); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done

mysql -uroot -e "ALTER TABLE employees.titles DISCARD TABLESPACE;"
