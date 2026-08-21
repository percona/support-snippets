#!/bin/bash
# Initial state: 3-node `interview` replica set. node3 was put under a backup-style write
# lock by `db.fsyncLock()` and never unlocked. With the global lock held,
# the oplog applier on node3 cannot commit batches, so node3's optime
# stops advancing while node1 keeps taking writes. Candidate runs
# `db.fsyncUnlock()` on node3 and replication catches up.
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

/usr/local/sbin/rs-bootstrap

if [ "${NODE_NAME:-$(hostname)}" = "node3" ]; then
    (
        set -e
        for _ in $(seq 1 240); do
            state=$(mongosh --quiet --eval 'rs.status().myState' 2>/dev/null || true)
            [ "$state" = "2" ] && break
            sleep 1
        done
        # fsyncLock right after SECONDARY can fail with "Cannot take
        # checkpoints when the stable timestamp is less than the initial
        # data timestamp" — WiredTiger hasn't established a stable
        # timestamp yet. Retry until it sticks.
        for _ in $(seq 1 60); do
            out=$(mongosh --quiet --eval '
              try { print((db.fsyncLock().lockCount > 0) ? "OK" : "NO"); }
              catch (e) { print("ERR " + e.message); }
            ' 2>/dev/null | tr -d '[:space:]')
            [ "$out" = "OK" ] && break
            sleep 2
        done
        echo "[fsyncLock] $(date -u +%FT%TZ) result=$out" \
            >>/var/log/rs-bootstrap.log
    ) &
fi

if [ "${NODE_INDEX:-0}" = "0" ]; then
    (
        set -e
        for _ in $(seq 1 240); do
            state=$(mongosh --quiet --eval 'rs.status().myState' 2>/dev/null || true)
            [ "$state" = "1" ] && break
            sleep 1
        done
        # Stream writes forever so the lag stays visible until the
        # candidate fixes it.
        mongosh --quiet --eval '
          while (true) {
            db.getSiblingDB("app").events.insertOne({ t: new Date(), n: Math.random() });
            sleep(2000);
          }
        ' >/dev/null 2>&1 &
    ) &
fi
