#!/bin/bash
# Initial state: a single server with employees already in the datadir and
# NO secondary index on titles. The reporting query therefore reads the
# whole table and finishes with a filesort. The candidate has to build an
# index covering the equality predicate AND the sort, with the range column
# last. An index that puts the range column before the sort column still
# leaves a filesort, and check.sh rejects it.
#
# This question used to spawn three replicating nodes, and nothing in it
# needed them: a candidate who happened to work on node2 hit super_read_only
# for no reason the question ever explained. nodes.txt now lists node1 only.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true

# Kept from the three-node days on purpose. With a single peer it only makes
# node1 writable and writes its "source=" line to the bootstrap log, and the
# smoke test waits for that line before it grades this level. Harmless, and
# it keeps this setup shaped like the multi-node questions.
/usr/local/sbin/repl-bootstrap

[ "${NODE_INDEX:-0}" = "0" ] || exit 0

# Drop any secondary index on titles, so the reporting query has to be served
# by the index the candidate builds. This runs INLINE, not in the background.
# It used to be backgrounded, which let setup return while the drop was still
# pending: the candidate's terminal (ttyd runs After=interview-setup) came up
# early, and a candidate who built the right index quickly could have it
# dropped from under them and fail a question they had solved. Inline, the
# terminal cannot appear until the index is gone. `bash -c` still execs, so
# nothing holds this script's descriptor, and it finishes before setup exits.
prune=$(cat <<'PRUNE'
for _ in $(seq 1 120); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done
mysql -uroot -N -B -e "
  SELECT DISTINCT CONCAT('ALTER TABLE employees.titles DROP INDEX \`', INDEX_NAME, '\`;')
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA='employees' AND TABLE_NAME='titles' AND INDEX_NAME<>'PRIMARY';" \
  2>/dev/null | mysql -uroot 2>/dev/null || true
PRUNE
)
bash -c "$prune" >>/var/log/repl-bootstrap.log 2>&1
