#!/bin/bash
# Pass when node3's oplog maxSize >= 5GB.
set -e

result=$(mongosh --quiet "mongodb://node3:27017/admin" --eval '
  try {
    const s = db.getSiblingDB("local").oplog.rs.stats();
    const gib = s.maxSize / (1024 * 1024 * 1024);
    print((s.maxSize >= 5 * 1024 * 1024 * 1024)
          ? "PASS"
          : ("FAIL maxSize=" + gib.toFixed(2) + "GB"));
  } catch (e) { print("FAIL: " + e.message); }
' 2>/dev/null || true)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: ${result:-unknown}"
        echo "Need: node3 oplog maxSize >= 5GB. Try replSetResizeOplog."
        exit 1
        ;;
esac
