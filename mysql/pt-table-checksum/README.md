# pt-table-checksum plugin

This plugin implements a custom `get_slave_lag` function that only checks the slave lag every n chunks.

## Why?
In some cases, like having slaves in different world regions, checking the slave lag is more expensive than calculating the checksums for each chunk.  
In those scenarios, it is better to have a way of skipping some of the slave lag checks to improve the program's performance.

## Usage

Set the `PT_SKIP_LAG_CHECK_COUNT` environment variable to the number of chunks between slave lag checks (default: 100) and run `pt-table-checksum` with `--plugin`.

### Example
```
PTDEBUG=1 PT_SKIP_LAG_CHECK_COUNT=2 bin/pt-table-checksum h=127.0.0.1,P=12345,u=msandbox,p=msandbox --plugin=/home/karl/go/src/github.com/percona/support-snippets/mysql/pt-table-checksum/check-slave-lag.pm
```
In the output you can see that on the 1st and 2nd chunks, slave lag is not being checked (`get_lag plugin: skipping lag check`) but on the 3rd chunk `get_slave_lag` is being executed (`slave lag: 0`)

```
# pt_table_checksum_plugin:42 5156 pt-table-checksum get_lag plugin: chunk_count 1
# pt_table_checksum_plugin:64 5156 pt-table-checksum get_lag plugin: skipping lag check
# ReplicaLagWaiter:8595 5156 karl-hp-omen slave lag: 0
# pt_table_checksum_plugin:42 5156 pt-table-checksum get_lag plugin: chunk_count 2
# pt_table_checksum_plugin:64 5156 pt-table-checksum get_lag plugin: skipping lag check
# ReplicaLagWaiter:8595 5156 karl-hp-omen slave lag: 0
# ReplicaLagWaiter:8628 5156 All slaves caught up
```
