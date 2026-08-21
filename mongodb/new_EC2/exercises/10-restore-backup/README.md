# Question 10 — Restore percona.company from backup

A customer engineer ran `db.getSiblingDB("percona").dropDatabase()` in
the wrong cluster. The application is down. You have a fresh
`mongodump` of `percona` on `node1` at `/backups/`.

Restore the `percona` database from `/backups` so the app can serve
queries again.
