#!/bin/bash
CURSTEP=$1
if [ "x$CURSTEP" == "xhelp" ] ; then
  echo "Usage ./$0 [NUM]"
  echo "Usage ./$0 999 # use for cleanup"
  echo "You can stop at any moment with CTRL+c and continue by running ./$0 NUMBER"
  exit 0
fi

if [ "x$CURSTEP" == "x" ] ; then
  CURSTEP=1
fi

MYPS='[postgres@pgslony84 ~]$ '
DLY=1

function introduce {
  while read -r -t 0; do read -r; done
  echo "# $CURSTEP. "$*
  read
  CURSTEP=$(( $CURSTEP+1 ))
}

if [ $CURSTEP -eq 1 ] ; then
  introduce "Check that all tables have a primary key:"
  echo "$MYPS"'pg_dump -s -U $PGBENCHUSER -h $MASTERHOST -n public $MASTERDBNAME|egrep -1 "CREATE TABLE|PRIMARY KEY"'
  sleep $DLY
  pg_dump -s -U $PGBENCHUSER -h $MASTERHOST -n public $MASTERDBNAME|egrep -1 'CREATE TABLE|PRIMARY KEY'
fi

if [ $CURSTEP -eq 2 ] ; then
  introduce "We have configured users and remote access on the new server and ready to copy schema (empty tables)"
  echo 'pg_dump -s -U $PGBENCHUSER -h $MASTERHOST -n public $MASTERDBNAME | psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME'
  sleep $DLY
  pg_dump -s -U $PGBENCHUSER -h $MASTERHOST -n public $MASTERDBNAME | psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME
fi

if [ $CURSTEP -eq 3 ] ; then
  introduce "configure Slony cluster"
  echo "$MYPS""cat 1.slonikinit.sh; ./1.slonikinit.sh"
  sleep $DLY
  cat 1.slonikinit.sh; ./1.slonikinit.sh
fi

if [ $CURSTEP -eq 4 ] ; then
  introduce "Where Slony stores the configuration?"
  echo "$MYPS"'psql pgbench -c "select * from pg_namespace;"'
  sleep $DLY
  psql pgbench -c "select * from pg_namespace;"
fi

if [ $CURSTEP -eq 5 ] ; then
  introduce "start slon daemons on both servers"
  echo "$MYPS"'slon -f master.conf &> master.log & (ssh $SLAVEHOST /usr/pgsql-11/bin/slon -f slave.conf) &> slave.log &'
  sleep $DLY
  slon -f master.conf &> master.log &
  (ssh $SLAVEHOST /usr/pgsql-11/bin/slon -f slave.conf) &> slave.log &
  jobs
fi


if [ $CURSTEP -eq 6 ] ; then
  introduce "Let's replicate table t1"
  echo "$MYPS"'cat 2.sloniksubscribe.sh; ./2.sloniksubscribe.sh'
  sleep $DLY
  cat 2.sloniksubscribe.sh; ./2.sloniksubscribe.sh
fi

if [ $CURSTEP -eq 7 ] ; then
  introduce "t1 on master"
  echo "$MYPS"'psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "select * from t1;"'
  sleep $DLY
  psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "select * from t1;"
fi

if [ $CURSTEP -eq 8 ] ; then
  introduce "t1 on slave"
  echo "$MYPS"'psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME -c "select * from t1;"'
  sleep $DLY
  psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME -c "select * from t1;"
fi

if [ $CURSTEP -eq 9 ] ; then
  introduce "let's modify t1"
  echo "$MYPS"'psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "insert into t1 (id) values(3);"'
  sleep $DLY
  psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "insert into t1 (id) values(3);"
fi

if [ $CURSTEP -eq 10 ] ; then
  introduce "t1 on master"
  echo "$MYPS"'psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "select * from t1;"'
  sleep $DLY
  psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "select * from t1;"
fi

if [ $CURSTEP -eq 11 ] ; then
  introduce "t1 on slave"
  echo "$MYPS"'psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME -c "select * from t1;"'
  sleep $DLY
  psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME -c "select * from t1;"
fi

if [ $CURSTEP -eq 12 ] ; then
  introduce "We are not limited just in one table"
  echo "$MYPS"'cat 3.slonikaddtable.sh;./3.slonikaddtable.sh'
  sleep $DLY
  cat 3.slonikaddtable.sh;./3.slonikaddtable.sh
fi

if [ $CURSTEP -eq 13 ] ; then
  introduce "When you will be ready to switch the application to slave, unsubscribe to disable replication"
  echo "$MYPS"'cat 4.slonikunsubscribe.sh; ./4.slonikunsubscribe.sh'
  sleep $DLY
  cat 4.slonikunsubscribe.sh; ./4.slonikunsubscribe.sh
fi

if [ $CURSTEP -eq 14 ] ; then
  introduce "Remove replica set"
  echo "$MYPS"'cat 5.slonikdropset.sh; ./5.slonikdropset.sh'
  sleep $DLY
  cat 5.slonikdropset.sh; ./5.slonikdropset.sh
fi

if [ $CURSTEP -eq 15 ] ; then
  introduce "Remove slony configuration schema from both servers"
  echo "$MYPS"'cat 6.slonikdropnodes.sh; ./6.slonikdropnodes.sh'
  sleep $DLY
  cat 6.slonikdropnodes.sh; ./6.slonikdropnodes.sh
fi

if [ $CURSTEP -eq 16 ] ; then
  introduce "Now we can kill slon daemons"
  echo "$MYPS"'pkill slon; ssh $SLAVEHOST pkill slon'
  sleep $DLY
  pkill slon; ssh $SLAVEHOST pkill slon
fi



if [ $CURSTEP -eq 999 ] ; then
  introduce "CLEANUP"
  pkill slon; ssh $SLAVEHOST pkill slon
  cat 6.slonikdropnodes.sh; ./6.slonikdropnodes.sh
  psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME -c "drop table pgbench_accounts,pgbench_branches,pgbench_history,pgbench_tellers,t1;"
  psql -U $PGBENCHUSER -h $MASTERHOST $MASTERDBNAME -c "delete from t1 where id > 1;"
fi

