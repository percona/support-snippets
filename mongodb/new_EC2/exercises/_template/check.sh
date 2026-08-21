#!/bin/bash
# Return 0 if the candidate has solved the question, non-zero otherwise.
# stdout/stderr is shown to the candidate when the check fails, so keep it
# helpful but don't leak the answer.
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/admin --eval '
  // Example: check that a collection exists.
  // print(db.getSiblingDB("demo").widgets.countDocuments({}));
  print("not solved")
')

case "$result" in
    "solved") exit 0 ;;
    *)        echo "Not solved yet."; exit 1 ;;
esac
