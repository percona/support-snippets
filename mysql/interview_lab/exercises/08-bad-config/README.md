# Question 8 — node3's mysqld will not start

`node3` has dropped out of the replication topology. `sudo systemctl status
mysqld` on node3 shows the service is failed and will not start back up.

Find the cause and bring node3 back as a healthy replica of node1.

Read the log after every attempt — mysqld reports one problem at a time.
If the error log itself is not telling you anything, try
`sudo journalctl -u mysqld`. The `sudo` matters: your user cannot read the
system journal on its own, so without it the command shows nothing useful.
