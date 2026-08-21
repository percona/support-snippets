#!/bin/bash
# Pass when percona.company has documents again.
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/admin --eval '
  try {
    const c = db.getSiblingDB("percona").company;
    const n = c.countDocuments({});
    print((n >= 90000) ? "PASS n=" + n : "FAIL n=" + n);
  } catch (e) { print("FAIL: " + e.message); }
' 2>/dev/null || true)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: ${result:-unknown}"
        echo "Need: percona.company has at least 90000 documents."
        exit 1
        ;;
esac
