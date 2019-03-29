#!/bin/bash
#
# This plugin examines threads that wait because of the semaphore wait and it is
# returning how long the longest-waiting thread waited in seconds.
#

trg_plugin() {
    maxWait=$(${MYSQL} -e "SHOW ENGINE INNODB STATUS\G"| awk \
        'BEGIN {o=0}
        /waited.*semaphore/
        {i=int($10); if(i>o) o=i;}
        END {print o}'
    );

    echo $maxWait;
}
