#!/bin/bash
# Pass when the reporting query runs from an index with no blocking sort:
# the winning plan contains an IXSCAN, and no COLLSCAN and no SORT stage.
# Any index that satisfies equality + sort qualifies, we do not require one
# exact key pattern.
set -e

result=$(mongosh --quiet mongodb://127.0.0.1:27017/admin --eval '
  try {
    const c = db.getSiblingDB("percona").company;
    const ex = c.find({ industry: "Tech", country: "US", founded: { $gte: 1910 } })
                .sort({ employees: -1 })
                .explain("executionStats");
    const plan = JSON.stringify(ex.queryPlanner.winningPlan);
    const has = (stage) => new RegExp("\"stage\"\\s*:\\s*\"" + stage + "\"").test(plan);
    if (has("COLLSCAN")) { print("FAIL: winning plan still does a COLLSCAN"); quit(); }
    if (!has("IXSCAN"))  { print("FAIL: winning plan does not use an index"); quit(); }
    if (has("SORT"))     { print("FAIL: winning plan still has a blocking SORT stage"); quit(); }
    const st = ex.executionStats || {};
    print("PASS examined=" + st.totalDocsExamined + " returned=" + st.nReturned +
          " ms=" + st.executionTimeMillis);
  } catch (e) { print("FAIL: " + e.message); }
' 2>/dev/null || true)

case "$result" in
    *PASS*) exit 0 ;;
    *)
        echo "Not solved: ${result:-unknown}"
        echo "Need: percona.company indexed so the query plan uses an IXSCAN and"
        echo "sorts by employees from the index (no COLLSCAN, no SORT stage)."
        exit 1
        ;;
esac
