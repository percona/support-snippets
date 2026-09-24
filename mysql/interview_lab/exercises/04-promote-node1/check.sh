#!/bin/bash
# Pass when:
#   - node1 is the source: writable (read_only = OFF and super_read_only =
#     OFF) and carrying no replica configuration at all
#   - node2 and node3 both replicate from node1 (named by hostname or by its
#     IP address) with both threads running
#   - both replicas are protected with super_read_only = ON
#
# "No replica configuration" is deliberate and the README says so in as many
# words: a STOP REPLICA on node1 leaves the channel to node2 in place, and
# replication starts again by itself on the next mysqld restart, pulling
# node2's writes back into the new source. Likewise super_read_only rather
# than read_only, because read_only still lets privileged accounts write to
# a replica. Both requirements are stated to the candidate, so the grader
# is exactly as strict as the question.
set -e

failed=""

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

conns=$(mysql -h node1 -uroot -N -B -e \
    "SELECT COUNT(*) FROM performance_schema.replication_connection_status;" 2>/dev/null || echo "x")
if [ "$conns" = "x" ]; then
    failed+="  node1: unreachable"$'\n'
elif [ "$conns" != "0" ]; then
    failed+="  node1: still carries replica configuration (a stopped replica resumes on restart; the channel has to be cleared)"$'\n'
fi

ro=$(mysql -h node1 -uroot -N -B -e "SELECT @@global.read_only, @@global.super_read_only;" 2>/dev/null || true)
case "$ro" in
    "0	0") ;;
    "")   failed+="  node1: could not read read_only flags"$'\n' ;;
    *)    failed+="  node1: not writable (read_only/super_read_only = ${ro})"$'\n' ;;
esac

for node in node2 node3; do
    out=$(mysql -h "$node" -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
    if [ -z "$out" ]; then
        failed+="  ${node}: unreachable, or not configured as a replica"$'\n'
        continue
    fi
    io=$(echo  "$out" | awk -F': *' '/Replica_IO_Running:/{print $2; exit}'  | tr -d '[:space:]')
    sql=$(echo "$out" | awk -F': *' '/Replica_SQL_Running:/{print $2; exit}' | tr -d '[:space:]')
    src=$(echo "$out" | awk -F': *' '/Source_Host:/{print $2; exit}'         | tr -d '[:space:]')
    sro=$(mysql -h "$node" -uroot -N -B -e "SELECT @@global.super_read_only;" 2>/dev/null | tr -d '[:space:]')
    points_at_node1 "$src" || failed+="  ${node}: source is '${src:-none}', expected node1 (by name or address)"$'\n'
    [ "$io"  = "Yes" ] || failed+="  ${node}: Replica_IO_Running=${io:-No}"$'\n'
    [ "$sql" = "Yes" ] || failed+="  ${node}: Replica_SQL_Running=${sql:-No}"$'\n'
    [ "$sro" = "1"   ] || failed+="  ${node}: super_read_only is OFF, replicas should be protected (read_only alone is not enough)"$'\n'
done

if [ -z "$failed" ]; then
    exit 0
fi

echo "Not solved:"
printf '%s' "$failed"
echo "Need: node1 writable and acting as source with no replica configuration left,"
echo "node2 and node3 replicating from it with both threads running and super_read_only ON."
exit 1
