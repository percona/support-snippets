#!/bin/bash
# Hold a steady pool of application connections against the local server.
#
# Each worker owns one connection and reconnects a few seconds after losing
# it, so the pool rebuilds itself automatically when mysqld is restarted —
# which is exactly what the candidate does to solve this question. Without
# the reconnect the pool would be empty at the moment they go to measure it.
#
# The pool size is chosen at random on each boot rather than hard-coded, so a
# candidate cannot read the expected answer out of this file: they have to
# query the running server and count the sessions the application account holds
# for themselves. The range stays well under max_connections so the pool
# always establishes fully.
N="${APP_CONNECTIONS:-$(( 30 + RANDOM % 11 ))}"

for _ in $(seq 1 "$N"); do
    (
        while true; do
            mysql -u appuser -pappuser -h 127.0.0.1 --protocol=tcp \
                  --connect-timeout=3 --get-server-public-key \
                  -e "SELECT SLEEP(86400)" \
                  >/dev/null 2>&1
            sleep 3
        done
    ) &
done
wait
