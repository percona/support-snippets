#!/bin/bash
# Pass when the replica set `interview` is healthy from EVERY node's own
# perspective: rs.status().ok == 1, set name is "interview", three members,
# exactly one PRIMARY and two SECONDARY.
set -e

RS_NAME=interview

probe() {
    mongosh --quiet --host "$1" --port 27017 --eval '
      try {
        const s = rs.status();
        const primary   = s.members.filter(m => m.state === 1).length;
        const secondary = s.members.filter(m => m.state === 2).length;
        const total     = s.members.length;
        if (s.ok !== 1)            { print("FAIL: rs.status not ok"); quit(); }
        if (s.set !== "'"$RS_NAME"'") { print("FAIL: set name is " + s.set); quit(); }
        if (total !== 3)           { print("FAIL: members=" + total); quit(); }
        if (primary !== 1)         { print("FAIL: primaries=" + primary); quit(); }
        if (secondary !== 2)       { print("FAIL: secondaries=" + secondary); quit(); }
        print("PASS");
      } catch (e) { print("FAIL: " + e.message); }
    ' 2>/dev/null || true
}

failed=""
for node in node1 node2 node3; do
    out=$(probe "$node")
    case "$out" in
        *PASS*) ;;
        *)      failed+="  ${node}: ${out:-unreachable}"$'\n' ;;
    esac
done

if [ -z "$failed" ]; then
    exit 0
fi

echo "Not solved:"
printf '%s' "$failed"
echo "Need: replica set \"${RS_NAME}\" with 1 PRIMARY + 2 SECONDARY, healthy on node1, node2 and node3."
exit 1
