#!/bin/bash
# Pass when percona.company contains the expected dataset.
# Spot-check: doc count >= 90000 AND sentinel doc _id=0 named "Company-000000".
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/percona --eval '
  const n = db.company.countDocuments({});
  const d = db.company.findOne({_id: 0});
  print((n >= 90000 && d && d.name === "Company-000000") ? "PASS" : ("FAIL n=" + n));
')

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: percona.company is not loaded with the expected dataset."
        exit 1
        ;;
esac
