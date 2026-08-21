#!/bin/bash
# Pass when BOTH tasks are done:
#   1. mongod is up and answering ping on 127.0.0.1:27017, and
#   2. /home/candidate/answer.txt holds the current open-connection count
#      (db.serverStatus().connections.current), within a small tolerance to
#      absorb the candidate's own lingering shells and this check's connection.
set -e

ANSWER_FILE="/home/candidate/answer.txt"
TOLERANCE=5

# --- task 1: mongod reachable ---
ping=$(mongosh --quiet --eval 'db.runCommand({ping:1}).ok' \
    mongodb://127.0.0.1:27017/admin 2>/dev/null || true)
if [ "$ping" != "1" ]; then
    echo "Not solved: mongod is not answering on 127.0.0.1:27017."
    exit 1
fi

# --- task 2: connection count written to answer.txt ---
if [ ! -s "$ANSWER_FILE" ]; then
    echo "Not solved: $ANSWER_FILE is empty or missing (write the current open-connection count there)."
    exit 1
fi

candidate=$(tr -cd '0-9' < "$ANSWER_FILE")
if [ -z "$candidate" ]; then
    echo "Not solved: $ANSWER_FILE does not contain a number."
    exit 1
fi

live=$(mongosh --quiet --eval 'print(db.serverStatus().connections.current)' \
    mongodb://127.0.0.1:27017/admin 2>/dev/null | tr -cd '0-9')
if [ -z "$live" ]; then
    echo "Not solved: could not read connections.current from mongod."
    exit 1
fi

diff=$(( candidate - live )); diff=${diff#-}
if [ "$diff" -le "$TOLERANCE" ]; then
    exit 0
fi

echo "Not solved: the connection count in $ANSWER_FILE doesn't match the server's current open connections."
exit 1
