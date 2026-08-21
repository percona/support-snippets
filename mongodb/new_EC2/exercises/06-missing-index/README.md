# Question 6 — Slow query on percona.company

The reporting team complains that this query is slow. It runs on
`percona.company`, which holds 100,000 documents:

```
db.getSiblingDB("percona").company.find({
  industry: "Tech",
  country: "US",
  founded: { $gte: 1910 }
}).sort({ employees: -1 })
```

`explain("executionStats")` shows a `COLLSCAN` over the whole collection
and a blocking in-memory `SORT`.

Make the query use an index, so the winning plan has **no COLLSCAN and
no SORT stage**. Check `executionStats` before and after, the timing
should drop.
