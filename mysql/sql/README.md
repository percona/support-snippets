# collect_dataset_size_per_engine.sql

This batch script is used to get logical dataset size per MySQL engine.

## Why?

The provides an overview of what database engine(s) is primarily used. You can use information as one of the factors on whether the current MySQL and OS configuration are still optimal for this system.

## Usage

Contents of the script can be run in batch mode or copied and pasted to MySQL console.

### Example

````
$ mysql -u root < collect_dataset_size_per_engine.sql
````

In the output below, the number of tables, rows, data size, index size and its ratio are shown. 
````
mysql: [Warning] Using a password on the command line interface can be insecure.
engine	tables	rows	data	idx	total_size	idxfrac
InnoDB	49	48.61M	10.81G	0.29G	11.10G	0.03
MyISAM	10	0.00M	0.00G	0.00G	0.00G	0.14
MEMORY	63	NULL	0.00G	0.00G	0.00G	NULL
CSV	2	0.00M	0.00G	0.00G	0.00G	NULL
PERFORMANCE_SCHEMA	87	1.43M	0.00G	0.00G	0.00G	NULL
NULL	100	NULL	NULL	NULL	NULL	NULL
````

With this information, you can infer that MySQL server uses InnoDB, 49 InnoDB tables, and around 11G of dataset.

## Caution 

Huge number of tables can slowness in performing this script and can impact server performance. Aside from setting innodb_stats_on_metadata to 0, it's best to run this during off peak hours.
