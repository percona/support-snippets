#!/bin/bash
# Initial state: the 3-node `interview` replica set was healthy, then node3's
# mongod.conf was edited with FOUR faults, no telltale comments and no
# duplicate top-level keys. The candidate has to read the file and recognise
# each bad value. mongod surfaces them one at a time, so removing only the
# first one is never enough.
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

/usr/local/sbin/rs-bootstrap

[ "${NODE_NAME:-$(hostname)}" = "node3" ] || exit 0

(
    set -e
    for _ in $(seq 1 240); do
        state=$(mongosh --quiet --eval 'rs.status().myState' 2>/dev/null || true)
        [ "$state" = "2" ] && break
        sleep 1
    done

    systemctl stop mongod || true

    # Fault 4, and the nastiest one: replSetName is "lnterview" (lowercase L)
    # instead of "interview". mongod starts happily with it, so this one only
    # shows up after the storage faults are fixed: node3 comes up but never
    # joins, node1 reports it unreachable / "replica set IDs do not match",
    # and node3's own rs.status() says it is not a member of the config.
    sed -i 's/^\([[:space:]]*replSetName:\).*/\1 lnterview/' /etc/mongod.conf

    # Faults 1-3 keep mongod from starting at all, each surrounded by
    # plausible, harmless tuning knobs:
    #   1. engine: mmapv1            -> unsupported storage engine in PSMDB 7
    #   2. directoryPerDB: true      -> conflicts with the existing dbPath
    #                                   (recorded in WiredTiger metadata at
    #                                   creation; cannot be toggled on later)
    #   3. directoryForIndexes: true -> same kind of on-disk conflict
    # The remaining knobs (syncPeriodSecs, cacheSizeGB, compressors,
    # prefixCompression) are runtime-safe and must stay startable.
    sed -i '/^storage:/r /dev/stdin' /etc/mongod.conf <<'EOF'
  directoryPerDB: true
  syncPeriodSecs: 60
  engine: mmapv1
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
      directoryForIndexes: true
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true
EOF

    systemctl start mongod || true
) &
