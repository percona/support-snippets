# Question 7 — node3 is falling behind

`SHOW REPLICA STATUS` on `node3` reports `Replica_IO_Running: Yes` and
`Replica_SQL_Running: Yes`, but `Seconds_Behind_Source` is climbing and
never comes back down. node2 is keeping up fine, and writes on node1 are
succeeding, so the source itself looks healthy.

A backup script ran on node3 last night.

Find why node3 isn't applying its relay log and fix it. The lag should drop
to ~0 once you do.
