#!/bin/bash
# Pass when:
#   - the replica set is healthy with 1 PRIMARY + 2 SECONDARY
#   - PRIMARY is node1
#   - node1's priority is strictly higher than every other member's, so it
#     also wins the next election (a bare stepDown on node2 is not enough)
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/admin --eval '
  try {
    const s = rs.status();
    const c = rs.conf();
    const primary = s.members.find(m => m.state === 1);
    const secondary = s.members.filter(m => m.state === 2).length;
    const node1Conf = c.members.find(m => m.host.startsWith("node1:"));
    const others    = c.members.filter(m => !m.host.startsWith("node1:"));
    if (s.ok !== 1) { print("FAIL: rs.status not ok"); quit(); }
    if (s.members.length !== 3) { print("FAIL: not 3 members"); quit(); }
    if (!primary) { print("FAIL: no PRIMARY"); quit(); }
    if (!primary.name.startsWith("node1:")) { print("FAIL: PRIMARY is " + primary.name); quit(); }
    if (secondary !== 2) { print("FAIL: secondaries=" + secondary); quit(); }
    if (!node1Conf) { print("FAIL: node1 not in rs.conf()"); quit(); }
    const top = Math.max(...others.map(m => m.priority));
    if (!(node1Conf.priority > top)) {
      print("FAIL: node1 priority=" + node1Conf.priority + ", highest other=" + top);
      quit();
    }
    print("PASS");
  } catch (e) { print("FAIL: " + e.message); }
' 2>/dev/null || true)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: ${result:-unknown}"
        echo "Need: node1 PRIMARY with two healthy SECONDARY members, and node1's"
        echo "priority higher than node2's and node3's so it stays preferred."
        exit 1
        ;;
esac
