# Question 4 — The application cannot write

The application is failing on every write:

```
ERROR 1290 (HY000): The MySQL server is running with the --super-read-only
option so it cannot execute this statement
```

Reads are working fine. The application connects to **node1** and expects to
write there.

Put the topology back the way the application expects. Precisely, when you
are done:

- **node1** is the source: writable (`read_only` and `super_read_only` both
  OFF) and **not configured as a replica of anything**. Stopping its
  replication threads is not enough — a stopped replica starts replicating
  again on the next `mysqld` restart, which would pull the other node's
  writes back into node1 — so clear its replica configuration entirely.
- **node2** and **node3** replicate from node1 with both threads running,
  and are protected with **`super_read_only = ON`**. Plain `read_only` is
  not enough: it still lets privileged accounts write to a replica.

> Replication account: user `repl`, password `repl`. Reach the other nodes
> with `mysql -h node2`. Name the source by hostname or by IP address,
> whichever you prefer — both are accepted.
