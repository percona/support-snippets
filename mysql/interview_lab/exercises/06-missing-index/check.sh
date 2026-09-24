#!/bin/bash
# Pass when the reporting query runs from a real index with no blocking
# sort: no full scan, no full index scan, and no filesort.
#
# The plan alone is not enough to grade on. InnoDB estimates from sampled
# pages, and this query sits near the optimizer's cost threshold, so even with
# the right index it can come out as a range scan plus a filesort after one
# CREATE INDEX and a clean ordered scan after the next. The image raises
# innodb_stats_persistent_sample_pages to make that rare. As a backstop, an
# index that leads with (title, to_date) also passes, because it is the answer
# whatever the estimate did that time. An index that puts from_date before
# to_date can never avoid the sort, so the backstop never passes it.
set -e

plan=$(mysql -uroot -N -B -e "
  EXPLAIN FORMAT=JSON
  SELECT * FROM employees.titles
  WHERE title = 'Engineer' AND from_date >= '1990-01-01'
  ORDER BY to_date DESC;" 2>/dev/null || true)

if [ -z "$plan" ]; then
    echo "Not solved: could not EXPLAIN the query (is mysqld up and employees.titles present?)."
    exit 1
fi

if ! echo "$plan" | grep -qE '"access_type": *"(ALL|index)"' &&
   ! echo "$plan" | grep -q '"using_filesort": *true' &&
   echo "$plan" | grep -q '"key":'; then
    exit 0
fi

# Visible secondary indexes on titles, one per line, columns in index order.
# A prefix part prints as col(N) so it does not count as the full column.
indexes=$(mysql -uroot -N -B -e "
  SELECT GROUP_CONCAT(IF(SUB_PART IS NULL, COLUMN_NAME, CONCAT(COLUMN_NAME,'(',SUB_PART,')'))
                      ORDER BY SEQ_IN_INDEX SEPARATOR ',')
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA='employees' AND TABLE_NAME='titles'
    AND INDEX_NAME<>'PRIMARY' AND IS_VISIBLE='YES'
  GROUP BY INDEX_NAME;" 2>/dev/null || true)

if printf '%s\n' "$indexes" | grep -qE '^title,to_date(,|$)'; then
    exit 0
fi

if echo "$plan" | grep -qE '"access_type": *"(ALL|index)"'; then
    echo "Not solved: the plan is still scanning the whole table."
elif echo "$plan" | grep -q '"using_filesort": *true'; then
    echo "Not solved: the plan still does a filesort."
    echo "Hint: the column you ORDER BY has to come before the range column in the index."
else
    echo "Not solved: the plan does not use an index."
fi
exit 1
