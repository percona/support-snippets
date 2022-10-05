#!/usr/local/pgsql/bin/slonik
define CLUSTER slony;
define PRIMARY 1;
define SLAVE 10;
cluster name = @CLUSTER;

node @PRIMARY admin conninfo = 'dbname=pgbench host=pgslony84 port=5432 user=postgres password=secret';

node @SLAVE admin conninfo = 'dbname=pgbench host=pgslony11 port=5432 user=postgres password=secret';

init cluster (id=@PRIMARY, comment='Primary Slony Node');

store node (id=@SLAVE, event node=@PRIMARY, comment='Slave Slony Node');

store path (server=@PRIMARY, client=@SLAVE, conninfo='dbname=pgbench host=pgslony84 port=5432 user=postgres password=secret');

store path (server=@SLAVE, client=@PRIMARY, conninfo='dbname=pgbench host=pgslony11 port=5432 user=postgres password=secret');

