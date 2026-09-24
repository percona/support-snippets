# Question 10 — The database is gone

The application is down. A customer engineer was working on what they
thought was a staging server:

```
mysql> DROP DATABASE employees;
Query OK, 8 rows affected (2.31 sec)
```

There is a **Percona XtraBackup** of this instance on the box at
`/backups/full`. It is a raw backup — it has not been prepared.

Get the application's data back.

> How you do it is your call — the check looks at the data, not at the
> route you took.
