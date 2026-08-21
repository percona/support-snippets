#!/bin/bash
# Pass when rs.status() on node1 shows the `interview` set with node3 back as
# a healthy member (PRIMARY or SECONDARY).
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/admin --eval '
  try {
    const s = rs.status();
    if (s.set !== "interview") { print("FAIL: set name is " + s.set); quit(); }
    const node3 = s.members.find(m => m.name.startsWith("node3:"));
    if (!node3) { print("FAIL: node3 not in rs"); quit(); }
    if (node3.health !== 1) { print("FAIL: node3 health=" + node3.health); quit(); }
    if (node3.state !== 1 && node3.state !== 2) {
      print("FAIL: node3 state=" + node3.stateStr);
      quit();
    }
    print("PASS");
  } catch (e) { print("FAIL: " + e.message); }
' 2>/dev/null || true)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: ${result:-unknown}"
        echo "Need: node3 healthy, state PRIMARY or SECONDARY."
        exit 1
        ;;
esac
