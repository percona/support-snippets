# Question 6 — Slow reporting query

The reporting team complains that this query is slow. It runs on
`employees.titles`, which holds over 440,000 rows:

```sql
SELECT * FROM employees.titles
WHERE title = 'Engineer'
  AND from_date >= '1990-01-01'
ORDER BY to_date DESC;
```

`EXPLAIN` shows it reading the whole table and finishing with
`Using filesort`.

Make the query run from an index, so the plan has **no full scan and no
filesort**. Check `EXPLAIN` before and after — the timing should drop.

> Any index that gets the plan there is fine; the check looks at the plan,
> not at one particular definition.

> The query returns over 100,000 rows. Do not run it bare to time it — this
> browser terminal will choke on the output. `EXPLAIN ANALYZE` executes the
> query and reports the actual time spent in each step without printing a
> row, or set `pager cat > /dev/null` in the `mysql` client first and read
> the `rows in set (N sec)` line.
