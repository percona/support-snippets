#!/usr/local/pgsql/bin/slonik
define CLUSTER slony;
define PRIMARY 1;
define SLAVE 10;
cluster name = @CLUSTER;

node @PRIMARY admin conninfo = 'dbname=pgbench host=pgslony84 port=5432 user=postgres password=secret';

node @SLAVE admin conninfo = 'dbname=pgbench host=pgslony11 port=5432 user=postgres password=secret';


subscribe set (id = 1, provider = @PRIMARY, receiver = @SLAVE);

