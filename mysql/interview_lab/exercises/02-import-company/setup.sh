#!/bin/bash
# The employees database is baked into the image's datadir, so for THIS
# question it has to be taken away again — the candidate's job is to load it.
# The dump they are given is the genuine upstream one.
#
# Staged in the candidate's home, not /tmp. /tmp is a tmpfs here, and tmpfs
# pages are anonymous memory charged to the container's 1 GB cap with no swap
# to fall back on: the tarball plus its ~168 MB of extracted dump, on top of
# a running mysqld, crosses the cap and the OOM killer takes mysqld mid-import,
# which looks to the candidate exactly like a broken lab. /home is disk, whose
# page cache the kernel can reclaim.
#
# The README names the directory but deliberately never spells out
# /home/candidate/<file>: the controller reads that pattern as "the file this
# question asks you to write" and pre-fills the Files panel with it, and one
# Save there would truncate the dump.
set -e

mysql -uroot -e "DROP DATABASE IF EXISTS employees;"

install -m 644 -o candidate -g candidate \
    /opt/employees-db.tar.gz /home/candidate/employees-db.tar.gz
