#!/bin/bash
# Pass when node2 and node3 are both healthy GTID replicas of node1 that
# actually hold the data and are actually applying it live:
#   - Replica_IO_Running = Yes and Replica_SQL_Running = Yes
#   - Auto_Position = 1 (GTID-based replication, which the question requires)
#   - the source is node1, named either by hostname or by its IP address
#   - the replica really has the employees data, not an empty datadir
#   - a write made on node1 now reaches the replica within a few seconds
# and node1 itself is not replicating from anyone.
#
# The data and flow checks exist because a replica can report IO=Yes/SQL=Yes
# while holding nothing. node1's employees database was loaded with binary
# logging off, so GTID auto-positioning does not back-fill it: a candidate who
# wipes node3's datadir, reinitialises an empty server and points it at node1
# gets both threads "running" against an empty database. Seeding the replica
# before attaching it is exactly the skill this question tests, so the grader
# has to look past the thread state at the data itself and at a live write.
#
# Time budget. The controller kills a sample at CHECK_TIMEOUT (20s) and
# records it as a failure it does not re-sample, so a correct topology that
# is merely slow to show the marker must never get near that. Worst case
# here: ~2s of status and row-count queries (a cold COUNT(*) included), then
# a FLOW_WAIT_MS window of 6s that both replicas share because it is measured
# from the write, not per replica, then one last poll: about 9s, and under 15s
# even if one connect stalls for its full 3s. The old per-replica 20s polls
# added up to 40s. A healthy replica applies the marker in milliseconds, and
# one that is only lagging is re-sampled by the controller for 30s anyway.
#
# Each failure is printed as soon as it is found, so a sample that is killed
# regardless still says what it had found.
set -e

FLOW_WAIT_MS=6000

failed=0
fail() {
    [ "$failed" = 1 ] || echo "Not solved:"
    failed=1
    echo "  $*"
}

# Every query goes through here. The connect cap means a node that stops
# answering costs 3s rather than the kernel's TCP connect timeout.
q() { local host=$1; shift; mysql --connect-timeout=3 -h "$host" -uroot "$@"; }
now_ms() { date +%s%3N; }

# The candidate may name the source 'node1' or use the address Docker gave
# it (a perfectly normal choice on a customer system), so compare addresses
# rather than strings. `getent` answers for a hostname and for an IP literal
# alike; this runs on node1, so resolving "node1" also covers the address
# the candidate saw in `hostname -I`. The literal match comes first so a DNS
# hiccup can never turn a correct 'node1' into a failure.
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

# node1 must be the source, not a replica.
n1=$(q node1 -N -B -e "SELECT COUNT(*) FROM performance_schema.replication_connection_status;" 2>/dev/null || echo "x")
if [ "$n1" = "x" ]; then
    fail "node1: unreachable"
elif [ "$n1" != "0" ]; then
    fail "node1: is replicating from another host, it should be the source"
fi

for node in node2 node3; do
    out=$(q "$node" -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
    if [ -z "$out" ]; then
        fail "${node}: unreachable, or it is not configured as a replica"
        continue
    fi
    io=$(echo  "$out" | awk -F': *' '/Replica_IO_Running:/{print $2; exit}'  | tr -d '[:space:]')
    sql=$(echo "$out" | awk -F': *' '/Replica_SQL_Running:/{print $2; exit}' | tr -d '[:space:]')
    src=$(echo "$out" | awk -F': *' '/Source_Host:/{print $2; exit}'         | tr -d '[:space:]')
    ap=$(echo  "$out" | awk -F': *' '/Auto_Position:/{print $2; exit}'       | tr -d '[:space:]')
    points_at_node1 "$src" || fail "${node}: source is '${src:-none}', expected node1 (by name or address)"
    [ "$io"  = "Yes" ] || fail "${node}: Replica_IO_Running=${io:-No}"
    [ "$sql" = "Yes" ] || fail "${node}: Replica_SQL_Running=${sql:-No}"
    [ "$ap"  = "1"   ] || fail "${node}: Auto_Position=${ap:-0}, GTID-based replication is required (SOURCE_AUTO_POSITION=1)"

    # The replica has to actually hold the data. A count on the source's
    # largest table is a cheap, decisive way to tell a seeded replica from an
    # empty one that merely reports the threads running.
    cnt=$(q "$node" -N -B -e "SELECT COUNT(*) FROM employees.employees;" 2>/dev/null | tr -cd '0-9')
    if [ -z "$cnt" ] || [ "$cnt" -lt 290000 ] 2>/dev/null; then
        fail "${node}: employees.employees has ${cnt:-no} rows — the replica was attached without its baseline data"
    fi
done

# Flow test: prove replication is live, not merely configured. Write a unique
# marker into a lab-owned table on node1 and poll each replica for it. This is
# what distinguishes a working topology from one that is wired up but stalled,
# and it also catches an empty replica that would never receive the row.
# Every replica gets the same window from the write and at least one poll.
if [ "$n1" = "0" ]; then
    token="flow-$(date +%s)-${RANDOM}-$$"
    # Guarded rather than left to set -e: a failed write would otherwise end
    # the check silently, with nothing printed to say why.
    if q node1 -e "
        CREATE DATABASE IF NOT EXISTS repl_flowcheck;
        CREATE TABLE IF NOT EXISTS repl_flowcheck.marker (id INT PRIMARY KEY, token VARCHAR(64));
        REPLACE INTO repl_flowcheck.marker (id, token) VALUES (1, '${token}');" >/dev/null 2>&1; then
        deadline=$(( $(now_ms) + FLOW_WAIT_MS ))
        for node in node2 node3; do
            arrived=0
            while :; do
                got=$(q "$node" -N -B -e "SELECT token FROM repl_flowcheck.marker WHERE id=1;" 2>/dev/null | tr -d '[:space:]')
                [ "$got" = "$token" ] && { arrived=1; break; }
                [ "$(now_ms)" -lt "$deadline" ] || break
                sleep 0.5
            done
            [ "$arrived" = 1 ] || fail "${node}: a write made on node1 did not arrive within $((FLOW_WAIT_MS / 1000))s — replication is configured but not live"
        done
    else
        fail "node1: could not write the flow-check marker (repl_flowcheck.marker), so live replication could not be tested"
    fi
fi

if [ "$failed" = 0 ]; then
    exit 0
fi

echo "Need: node1 as source, with node2 and node3 both replicating from it via GTID"
echo "(Auto_Position=1), both threads running, holding the data, and a fresh write on"
echo "node1 reaching them within a few seconds."
exit 1
