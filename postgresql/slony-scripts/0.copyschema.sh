#!/usr/bin/bash
pg_dump -s -U $PGBENCHUSER -h $MASTERHOST -n public $MASTERDBNAME | psql -U $PGBENCHUSER -h $SLAVEHOST $SLAVEDBNAME
