#!/bin/bash
# Initial state: 3-node `interview` replica set, percona.company loaded with
# 100k documents and NO index except _id. The reporting query
#   find({industry:"Tech", country:"US", founded:{$gte:1910}}).sort({employees:-1})
# therefore does a COLLSCAN plus a blocking SORT. The candidate has to build
# an index that covers the equality predicates and the sort, following ESR:
#   { industry: 1, country: 1, employees: -1, founded: 1 }
# An index that stops at the range field still leaves a SORT stage, and
# check.sh rejects it.
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

/usr/local/sbin/rs-bootstrap

[ "${NODE_INDEX:-0}" = "0" ] || exit 0

# Background: wait for PRIMARY, then load data and drop every secondary index.
(
    set -e
    for _ in $(seq 1 240); do
        state=$(mongosh --quiet --eval 'rs.status().myState' 2>/dev/null || true)
        [ "$state" = "1" ] && break
        sleep 1
    done

    tar -xzf /opt/company.json.tar.gz -C /tmp/
    mongoimport --quiet \
        --host 127.0.0.1 --port 27017 \
        --db percona --collection company --drop \
        --numInsertionWorkers 4 \
        --file /tmp/company.json

    rm -f /tmp/company.json

    mongosh --quiet --eval '
      const c = db.getSiblingDB("percona").company;
      c.getIndexes()
        .filter(i => i.name !== "_id_")
        .forEach(i => c.dropIndex(i.name));
    ' >/var/log/rs-bootstrap.log 2>&1 || true
) &
