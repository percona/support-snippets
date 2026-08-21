# Question 9 — Read mongod version from a customer FTDC file

A customer escalated a ticket with one FTDC chunk attached. We need
to confirm which mongod version the customer was running before we
can match it to a known-issue list.

The file is at `/opt/customer-ftdc/metrics.bson`.

Find the **mongod version string** recorded in that file (e.g.
`6.0.4-3`) and write it to `/home/candidate/answer.txt`.
