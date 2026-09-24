#!/bin/bash
# Pass when node3 is applying again: Seconds_Behind_Source within 5s and the
# SQL thread running.
set -e

out=$(mysql -h node3 -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null || true)
if [ -z "$out" ]; then
    echo "Not solved: node3 is unreachable, or it is not configured as a replica."
    exit 1
fi

io=$(echo  "$out" | awk -F': *' '/Replica_IO_Running:/{print $2; exit}' | tr -d '[:space:]')
sql=$(echo "$out" | awk -F': *' '/Replica_SQL_Running:/{print $2; exit}'      | tr -d '[:space:]')
lag=$(echo "$out" | awk -F': *' '/Seconds_Behind_Source:/{print $2; exit}'    | tr -d '[:space:]')

# BOTH threads must be running. Checking only the SQL thread is not enough:
# if the IO thread is dead the replica is not receiving anything, the SQL
# thread still reports "Yes" because it has nothing left to apply, and
# Seconds_Behind_Source stops meaning anything. That combination let this
# check pass on a replica that was not replicating at all.
if [ "$io" != "Yes" ]; then
    echo "Not solved: Replica_IO_Running=${io:-No} on node3 - it is not receiving from the source."
    exit 1
fi

if [ "$sql" != "Yes" ]; then
    echo "Not solved: Replica_SQL_Running=${sql:-No} on node3."
    exit 1
fi

case "$lag" in
    ''|NULL)
        echo "Not solved: node3 reports Seconds_Behind_Source=${lag:-unknown}."
        exit 1 ;;
esac

if [ "$lag" -le 5 ] 2>/dev/null; then
    exit 0
fi

echo "Not solved: node3 is ${lag}s behind the source."
echo "Need: Seconds_Behind_Source within 5s of the source."
exit 1
