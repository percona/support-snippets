#!/bin/bash
# Pass when node3 is back as a healthy replica of node1, with both
# replication threads running.
set -e

out=$(mysql -h node3 -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
if [ -z "$out" ]; then
    echo "Not solved: node3 is unreachable, or it is not configured as a replica."
    exit 1
fi

io=$(echo  "$out" | awk -F': *' '/Replica_IO_Running:/{print $2; exit}'  | tr -d '[:space:]')
sql=$(echo "$out" | awk -F': *' '/Replica_SQL_Running:/{print $2; exit}' | tr -d '[:space:]')
src=$(echo "$out" | awk -F': *' '/Source_Host:/{print $2; exit}'         | tr -d '[:space:]')

# The bootstrap pointed node3 at 'node1' by name, but a candidate who
# re-issues CHANGE REPLICATION SOURCE while repairing the node may well use
# the address Docker gave node1 instead, which is just as correct. Compare
# addresses rather than strings: `getent` answers for a hostname and for an
# IP literal alike, and this runs on node1, so resolving "node1" gives the
# address the candidate would have seen in `hostname -I`. The literal match
# comes first so a DNS hiccup can never turn a correct 'node1' into a
# failure.
resolve() { getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
points_at_node1() {
    local src=$1 want ip
    [ "$src" = "node1" ] && return 0
    [ -n "$src" ] || return 1
    want=$(resolve node1)
    [ -n "$want" ] || return 1
    for ip in $(resolve "$src"); do
        printf '%s\n' "$want" | grep -qxF "$ip" && return 0
    done
    return 1
}

fail=""
points_at_node1 "$src" || fail+="  source is '${src:-none}', expected node1 (by name or address)"$'\n'
[ "$io"  = "Yes" ] || fail+="  Replica_IO_Running=${io:-No}"$'\n'
[ "$sql" = "Yes" ] || fail+="  Replica_SQL_Running=${sql:-No}"$'\n'

# The planted fault set node3's server_id to node1's. Checking only the thread
# state lets a candidate "fix" it by colliding node3 with node2 instead: 8.0
# matches dump threads by server_uuid, so both replicas stay connected and the
# duplicate id is still there. Assert node3's server_id differs from BOTH peers.
sid1=$(mysql -h node1 -uroot -N -B -e "SELECT @@server_id;" 2>/dev/null | tr -cd '0-9')
sid2=$(mysql -h node2 -uroot -N -B -e "SELECT @@server_id;" 2>/dev/null | tr -cd '0-9')
sid3=$(mysql -h node3 -uroot -N -B -e "SELECT @@server_id;" 2>/dev/null | tr -cd '0-9')
if [ -z "$sid3" ]; then
    fail+="  could not read node3's server_id"$'\n'
else
    [ -n "$sid1" ] && [ "$sid3" = "$sid1" ] && fail+="  server_id (${sid3}) still collides with node1 — give node3 an id unique in the topology"$'\n'
    [ -n "$sid2" ] && [ "$sid3" = "$sid2" ] && fail+="  server_id (${sid3}) now collides with node2 — the id must differ from every node, not just node1"$'\n'
fi

# The fix must not "work" by breaking node2. Re-confirm node2 is still a
# healthy replica of node1: a node3 server_id that collides with node2 would
# knock node2's replication out, and this catches that too.
out2=$(mysql -h node2 -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
if [ -z "$out2" ]; then
    fail+="  node2 is unreachable or no longer a replica — the fix must not disturb node2"$'\n'
else
    io2=$(echo  "$out2" | awk -F': *' '/Replica_IO_Running:/{print $2; exit}'  | tr -d '[:space:]')
    sql2=$(echo "$out2" | awk -F': *' '/Replica_SQL_Running:/{print $2; exit}' | tr -d '[:space:]')
    src2=$(echo "$out2" | awk -F': *' '/Source_Host:/{print $2; exit}'         | tr -d '[:space:]')
    points_at_node1 "$src2" || fail+="  node2: source is '${src2:-none}', expected node1"$'\n'
    [ "$io2"  = "Yes" ] || fail+="  node2: Replica_IO_Running=${io2:-No} (the fix broke node2)"$'\n'
    [ "$sql2" = "Yes" ] || fail+="  node2: Replica_SQL_Running=${sql2:-No} (the fix broke node2)"$'\n'
fi

if [ -z "$fail" ]; then
    exit 0
fi

echo "Not solved:"
printf '%s' "$fail"
echo "Need: node3 up and replicating from node1 with both threads running and a"
echo "server_id unique across the topology, and node2 still a healthy replica."
exit 1
