#!/bin/bash
# Initial state: 3-node `interview` replica set. /backups on node1 contains a mongodump of
# the percona DB. percona.company has been dropped from the live cluster.
# Candidate runs `mongorestore /backups` (or with --host).
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

/usr/local/sbin/rs-bootstrap

[ "${NODE_INDEX:-0}" = "0" ] || exit 0

(
    set -e
    LOG=/var/log/rs-bootstrap.log
    for _ in $(seq 1 240); do
        state=$(mongosh --quiet --eval 'rs.status().myState' 2>/dev/null || true)
        [ "$state" = "1" ] && break
        sleep 1
    done

    tar -xzf /opt/company.json.tar.gz -C /tmp/
    mongoimport --quiet \
        --host 127.0.0.1 --port 27017 \
        --db percona --collection company --drop \
        --file /tmp/company.json >>"$LOG" 2>&1

    mkdir -p /backups
    mongodump --quiet \
        --host 127.0.0.1 --port 27017 \
        --db percona --out /backups >>"$LOG" 2>&1
    chown -R candidate:candidate /backups

    mongosh --quiet --eval '
      db.getSiblingDB("percona").dropDatabase();
    ' >>"$LOG" 2>&1
) &
