# Question 7 — node3 is lagging behind primary

`rs.status()` shows `node3` is `SECONDARY` but its optime is hundreds
of seconds behind the primary's, and the gap keeps growing. Writes
keep hitting node1 successfully, so the primary itself looks fine.

A backup script ran on node3 last night.

Find why node3 isn't applying its oplog and fix it. Lag should drop
to ~0 once you do.
