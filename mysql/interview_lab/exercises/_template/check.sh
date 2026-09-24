#!/bin/bash
# Return 0 if the candidate has solved the question, non-zero otherwise.
# Runs inside the FIRST node listed in nodes.txt. It is copied in at check
# time and removed afterwards, so it never sits on disk for a candidate to
# read.
set -e

result=$(mysql -uroot -N -B -e "SELECT 'not solved';" 2>/dev/null || true)

case "$result" in
    solved) exit 0 ;;
    *)      echo "Not solved yet."; exit 1 ;;
esac
