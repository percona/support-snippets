#!/bin/bash
# Pass when the candidate's query returns exactly the right employees, in
# the right order.
#
# Graded against reference queries run at check time rather than a hardcoded
# list, so it stays correct if the dataset is ever updated. Only the first
# column (emp_no) and its order are compared, and repeated emp_nos are
# collapsed — a candidate who joins titles and gets one row per title is not
# penalised for it.
#
# The customer's wording never says whether "an Engineer in d005" means the
# current assignment or anyone who has ever had one, and dept_emp and titles
# both keep history rows, so the two readings return different people: 37
# employees currently, 54 ever, against the real dataset. The README tells
# the candidate both readings count, so the grader accepts either result set
# and only insists that the submitted one is internally consistent and
# correctly ordered. "Held the title while in d005" (overlapping date
# ranges) yields the same 54 rows as the plain "ever" reading, and "currently
# in d005, any Engineer title ever held" yields the same 37 as "current", so
# those pass too without being listed separately.
#
# Ordering: the reference sorts by birth_date and then emp_no. The candidate
# was only asked for birth_date, so rows that share a birth_date may come
# back in any order; before comparing, each run of equal birth_dates in the
# candidate's output is re-sorted by emp_no, the same tiebreak the reference
# uses. That keeps the comparison deterministic without demanding a
# tiebreaker the question never mentioned. No two employees in either result
# set share a birth_date today; this guards against a future dataset where
# they do.
set -e

ANSWER="/home/candidate/answer.sql"

# Preserve the submitted query before the container is torn down, so the
# interviewer can see HOW they wrote it, not just whether it matched.
preserve() {
    # Each interview run now gets its own transcript directory, passed in as
    # HISTDIR (/var/log/history/<run_id>/level-<N>); the dashboard reads the
    # artifact from there and no longer falls back to the flat path once a run
    # id exists. Honour HISTDIR so the submitted query lands where the
    # controller looks, and keep the old per-level path for a run without one
    # (an older controller, or the smoke test).
    local dest="${HISTDIR:-/var/log/history/level-${LEVEL:-9}}"
    mkdir -p "$dest" 2>/dev/null || return 0
    cp -f "$ANSWER" "$dest/answer.sql" 2>/dev/null || true
}
trap preserve EXIT

if [ ! -s "$ANSWER" ]; then
    echo "Not solved: $ANSWER is empty or missing."
    exit 1
fi

# Run the candidate's file. A SQL error is worth showing the interviewer:
# a query that does not run is a different failure from one that returns
# the wrong people.
if ! raw=$(mysql -uroot -N -B employees < "$ANSWER" 2>&1); then
    echo "Not solved: the query failed to run:"
    printf '%s\n' "$raw" | head -n 3 | sed 's/^/  /'
    exit 1
fi
got=$(printf '%s\n' "$raw" | awk -F'\t' 'NF{print $1}' | awk '!seen[$0]++')

if [ -z "$got" ]; then
    echo "Not solved: the query returned no rows."
    exit 1
fi

# One reference per reading. Each returns "emp_no<TAB>birth_date", ordered by
# birth_date and then emp_no. EXISTS rather than JOIN so an employee with
# several matching rows still comes out once.
reference() {  # reference <extra dept_emp predicate> <extra titles predicate>
    mysql -uroot -N -B employees 2>/dev/null <<SQL
SELECT e.emp_no, e.birth_date
FROM employees e
WHERE e.last_name = 'Trumbly'
  AND EXISTS (SELECT 1 FROM dept_emp de
               WHERE de.emp_no = e.emp_no AND de.dept_no = 'd005' $1)
  AND EXISTS (SELECT 1 FROM titles t
               WHERE t.emp_no = e.emp_no AND t.title LIKE '%Engineer%' $2)
ORDER BY e.birth_date, e.emp_no;
SQL
}
ref_now=$(reference "AND de.to_date = '9999-01-01'" "AND t.to_date = '9999-01-01'")
ref_ever=$(reference "" "")

if [ -z "$ref_now" ] || [ -z "$ref_ever" ]; then
    echo "Not solved: could not run the reference query (is the employees database intact?)."
    exit 1
fi

count() { printf '%s\n' "$1" | grep -c . ; }

# Same employees, order ignored.
same_set() {  # same_set <reference pairs>
    [ "$(printf '%s\n' "$got" | sort -n)" = "$(printf '%s\n' "$1" | cut -f1 | sort -n)" ]
}

# Same order, with the tiebreak. Label each of the candidate's emp_nos with
# its birth_date (looked up from the reference, which same_set has already
# shown covers every one of them), number the runs of consecutive equal
# dates, sort each run by emp_no, and the result must be the reference
# sequence. A wrong direction or an interleaved date breaks the runs and
# fails; ties in a different order do not.
same_order() {  # same_order <reference pairs>
    local canon
    canon=$(awk -F'\t' '
        NR == FNR { born[$1] = $2; next }
        { d = born[$1]
          if (d != prev) { run++; prev = d }
          print run "\t" $1 }' \
        <(printf '%s\n' "$1") <(printf '%s\n' "$got") \
        | sort -t$'\t' -k1,1n -k2,2n | cut -f2)
    [ "$canon" = "$(printf '%s\n' "$1" | cut -f1)" ]
}

for ref in "$ref_now" "$ref_ever"; do
    if same_set "$ref"; then
        if same_order "$ref"; then
            exit 0
        fi
        echo "Not solved: the right employees ($(count "$ref") of them), but in the wrong order."
        echo "Need: oldest first, i.e. birth_date ascending."
        exit 1
    fi
done

echo "Not solved: the result matches neither accepted reading."
echo "  your query returned $(count "$got") distinct values in the first column (taken as emp_no)"
echo "  expected $(count "$ref_now") (currently in d005 with an Engineer title)"
echo "  or       $(count "$ref_ever") (ever in d005 and ever held an Engineer title)"
echo "Check that emp_no is the first column, the d005 join, the title match"
echo "(LIKE '%Engineer%', not = 'Engineer'), the surname, and that to_date is"
echo "handled the same way on dept_emp and titles."
exit 1
