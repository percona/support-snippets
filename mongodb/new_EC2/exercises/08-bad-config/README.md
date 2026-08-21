# Question 8 — node3's mongod will not start

`node3` is missing from the replica set `interview`. `sudo systemctl
status mongod` on node3 shows the service is failed and won't start back
up.

Find the cause and bring node3 back as a healthy SECONDARY. Read the log
after every attempt, mongod reports one problem at a time.
