#!/bin/bash
# Initial state: 3-node `interview` replica set. node3 has oplogSizeMB=990 set in mongod.conf
# so its oplog is created at 990MB. Candidate runs replSetResizeOplog on
# node3 to grow it to 5120MB.
set -e

systemctl is-active mongod >/dev/null || systemctl start mongod || true

if [ "${NODE_NAME:-$(hostname)}" = "node3" ]; then
    # node3 needs replSetName AND a small oplog. Writing both keys
    # together so rs-bootstrap's "is replication already there?" check
    # finds the block and doesn't double-add it.
    if ! grep -q '^replication:' /etc/mongod.conf; then
        cat >> /etc/mongod.conf <<'EOF'

replication:
  replSetName: interview
  oplogSizeMB: 990
EOF
        systemctl restart mongod
    fi
fi

/usr/local/sbin/rs-bootstrap
