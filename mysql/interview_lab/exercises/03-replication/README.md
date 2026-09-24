# Question 3 — Build a replication topology

The application team needs GTID-based asynchronous replication across
`node1`, `node2` and `node3`: **node1 as the source**, the other two as
replicas.

- `node1` and `node2` already have MySQL running, but standalone — nothing
  is replicating. Wire those two up first.
- `node3` **has had its Percona Server packages removed.** Somebody
  uninstalled the server and the client, so there is no `mysqld` and no
  `mysql` binary on it. The old `/etc/my.cnf` and the data directory under
  `/var/lib/mysql` — with the data and the accounts it had — are still on
  disk. Install Percona Server for MySQL again (the Percona repo is already
  configured on the box), then bring node3 into the topology alongside the
  others. Whether you reuse what is on disk or rebuild node3 from node1 is
  your call.

Set it up so node2 and node3 are both healthy replicas of node1, with the
IO and SQL threads running on each.

> There is more than one way to get node3 into the topology, and the check
> only looks at the end state — take whichever route you would take on a
> customer's system. Name the source by hostname or by IP address, whichever
> you prefer — both are accepted.

> A replication account already exists on every node: user `repl`, password
> `repl`. From node1 or node2 you can reach the other nodes with
> `mysql -h node2`; node3 has no `mysql` client until you have installed it.
