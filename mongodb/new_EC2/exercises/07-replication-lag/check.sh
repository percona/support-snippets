#!/bin/bash
# Pass when node3's optime is within 5 seconds of the primary's.
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/admin --eval '
  try {
    const s = rs.status();
    const primary = s.members.find(m => m.state === 1);
    const node3   = s.members.find(m => m.name.startsWith("node3:"));
    if (!primary || !node3) { print("FAIL: missing PRIMARY or node3"); quit(); }
    const lag = (primary.optimeDate.getTime() - node3.optimeDate.getTime()) / 1000;
    print((lag <= 5) ? "PASS lag=" + lag.toFixed(1) + "s"
                     : "FAIL lag=" + lag.toFixed(1) + "s");
  } catch (e) { print("FAIL: " + e.message); }
' 2>/dev/null || true)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: ${result:-unknown}"
        echo "Need: node3 optime within 5s of PRIMARY."
        exit 1
        ;;
esac
