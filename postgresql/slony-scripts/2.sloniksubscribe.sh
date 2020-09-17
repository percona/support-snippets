#!/usr/local/pgsql/bin/slonik
define CLUSTER slony;
define PRIMARY 1;
define SLAVE 10;
cluster name = @CLUSTER;

node @PRIMARY admin conninfo = 'dbname=pgbench host=pgslony84 port=5432 user=postgres password=secret';

node @SLAVE admin conninfo = 'dbname=pgbench host=pgslony11 port=5432 user=postgres password=secret';

create set (id=1, origin=@PRIMARY, comment='set1');

set add table (id=1, set id=1, origin = @PRIMARY, fully qualified name = 'public.t1', comment = 'table');

subscribe set (id = 1, provider = @PRIMARY, receiver = @SLAVE);

