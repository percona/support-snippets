#!/bin/bash
# Pass when employees.titles is queryable again with its full, genuine dataset.
# A row count alone would accept a table stuffed with synthetic rows, so also
# assert a known value that only the real data carries: emp_no 10001's current
# title. IMPORT TABLESPACE of the recovered file restores both the count and
# the values, so a legitimate recovery is unaffected.
set -e

n=$(mysql -uroot -N -B -e "SELECT COUNT(*) FROM employees.titles;" 2>/dev/null | tr -cd '0-9')
val=$(mysql -uroot -N -B -e "SELECT title FROM employees.titles WHERE emp_no=10001 AND from_date='1986-06-26';" 2>/dev/null | tr -d '\r')

if [ -n "$n" ] && [ "$n" -ge 430000 ] 2>/dev/null && [ "$val" = "Senior Engineer" ]; then
    exit 0
fi

echo "Not solved: employees.titles is still not readable with its full, genuine dataset (got '${n:-an error}' rows)."
echo "Need: the table queryable again, with at least 430000 rows and its real data intact."
exit 1
