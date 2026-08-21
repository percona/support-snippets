#!/bin/bash
# Pass when /home/candidate/answer.txt contains the version string
# embedded in /opt/customer-ftdc/metrics.bson (i.e. NOT the live mongod).
set -e

ANSWER_FILE="/home/candidate/answer.txt"
EXPECTED="5.0.29-25"

if [ ! -s "$ANSWER_FILE" ]; then
    echo "Not solved: $ANSWER_FILE is empty or missing."
    exit 1
fi

candidate=$(tr -d '[:space:]' < "$ANSWER_FILE")

case "$candidate" in
    *"$EXPECTED"*) exit 0 ;;
    *)
        echo "Not solved: answer ('$candidate') does not match the version recorded in /opt/customer-ftdc/metrics.bson."
        exit 1
        ;;
esac
