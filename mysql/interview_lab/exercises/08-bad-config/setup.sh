#!/bin/bash
# Initial state: the topology was healthy, then node3's configuration was edited
# to carry several independent faults, with no telltale comments and no
# duplicate keys, so the candidate has to read the files and recognise each bad
# value on its own. mysqld surfaces configuration problems one at a time, so
# fixing only the first is never enough, and one of the faults does not stop
# startup at all — it only bites once the server is running.
set -e

systemctl is-active mysqld >/dev/null || systemctl start mysqld || true

/usr/local/sbin/repl-bootstrap

[ "${NODE_NAME:-$(hostname)}" = "node3" ] || exit 0

# The fault injection waits for node3 to finish joining the topology and then
# edits its config, so it has to run in the background. It is launched with
# `nohup bash -c` so the exec drops the file descriptor this setup script is
# read from; a plain backgrounded subshell would keep it open and let this
# (soon-to-be-deleted) script be recovered from /proc/<pid>/fd while it runs.
inject=$(cat <<'INJECT'
set -e
for _ in $(seq 1 240); do
    io=$(mysql -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null \
         | awk -F': *' '/Replica_IO_Running:/{print $2; exit}' | tr -d '[:space:]')
    [ "$io" = "Yes" ] && break
    sleep 1
done

systemctl stop mysqld || true

# One fault is a server_id that duplicates another node in the topology. mysqld
# starts happily with it, so it only bites once the startup faults are cleared:
# the node comes up but its IO thread cannot coexist with the node it collides
# with, and replication never runs.
sed -i 's/^server_id.*/server_id   = 1/' /etc/my.cnf.d/99-node.cnf

# The earlier form of the fatal size fault used a 200G buffer pool. Do NOT go
# back to that: a candidate restarting mysqld made InnoDB map and touch 200 GB,
# and because a cgroup caps resident memory rather than address space, the
# kernel built enormous page tables and crash-looped hard enough to take the
# whole host down — nginx, controller and sshd with it. A size mismatch on a
# small on-disk file fails just as cleanly and allocates nothing.
sed -i 's#^log-error.*#log-error                = /var/log/mysql-archive/mysqld.log#' /etc/my.cnf

# The knobs inserted here are otherwise legitimate and must stay startable;
# exactly one of them is fatal on 8.0.
sed -i '/^\[mysqld\]/r /dev/stdin' /etc/my.cnf <<'CNF'
innodb_data_file_path          = ibdata1:64M:autoextend
query_cache_size               = 64M
innodb_flush_log_at_trx_commit = 1
innodb_log_buffer_size         = 16M
max_connections                = 200
tmp_table_size                 = 32M
CNF

systemctl start mysqld || true
INJECT
)
nohup bash -c "$inject" >/dev/null 2>&1 &
