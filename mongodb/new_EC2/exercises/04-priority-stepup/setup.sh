#!/bin/bash
# Initial state: replica set `interview` with node2 priority 10, others
# priority 1, so node2 wins every election. The candidate must reconfig
# node1 above node2 (any value > 10) and get node1 elected. check.sh only
# requires node1 PRIMARY and node1's priority strictly highest, not one
# specific number.
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

CONFIG='{
  _id: "interview",
  members: [
    { _id: 0, host: "node1:27017", priority: 1 },
    { _id: 1, host: "node2:27017", priority: 10 },
    { _id: 2, host: "node3:27017", priority: 1 }
  ]
}'

/usr/local/sbin/rs-bootstrap "$CONFIG"
