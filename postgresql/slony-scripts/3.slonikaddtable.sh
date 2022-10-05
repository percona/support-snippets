#!/usr/local/pgsql/bin/slonik
define CLUSTER slony;
define PRIMARY 1;
define SLAVE 10;
cluster name = @CLUSTER;

node @PRIMARY admin conninfo = 'dbname=pgbench host=pgslony84 port=5432 user=postgres password=secret';

node @SLAVE admin conninfo = 'dbname=pgbench host=pgslony11 port=5432 user=postgres password=secret';

UNSUBSCRIBE SET ( ID = 1, RECEIVER = @SLAVE);
set add table (set id=1, origin=1, id=2, fully qualified name = 'public.pgbench_accounts', comment='accounts table');
set add table (set id=1, origin=1, id=3, fully qualified name = 'public.pgbench_branches', comment='branches table');
set add table (set id=1, origin=1, id=4, fully qualified name = 'public.pgbench_tellers', comment='tellers table');
set add table (set id=1, origin=1, id=5, fully qualified name = 'public.pgbench_history', comment='history table');
subscribe set (id = 1, provider = @PRIMARY, receiver = @SLAVE);

