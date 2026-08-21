# Question 5 — Resize node3's oplog

The replica set is healthy, but `node3`'s oplog window is too short
to safely resync after a multi-hour outage. Capacity planning says
**5 GB** is the right size for this workload.

Resize node3's oplog to 5 GB (5120 MB). Don't touch node1 or node2.
