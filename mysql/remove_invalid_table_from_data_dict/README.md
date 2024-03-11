# Description
This is a patch for removing orphaned tables from the InnoDB table dictionary.

# How to use it

- patch MySQL 5.7.26
```
mkdir build
mkdir boost
wget https://codeload.github.com/mysql/mysql-server/zip/refs/tags/mysql-5.7.26
unzip mysql-5.7.26
cd mysql-server-mysql-5.7.26
git apply ${the path of the repo}/remove_invalid_table_from_data_dict.patch
```
- compile
```
cmake -B ../build -DDOWNLOAD_BOOST=1 -DWITH_BOOST=../boost
cd ../build
make -j 8
```

- start the self-compiled mysqld
```
mysqladmin shutdown
./sql/mysqld --defaults-file=${the configuration file}
```

- start the normal mysqld
```
mysqladmin shutdown
systemctl start mysql
```

# test

## Before the patch
> there is one orphaned data file in my test instance.

```
mysql [localhost:5741] {msandbox} ((none)) > SELECT * FROM INFORMATION_SCHEMA.INNODB_SYS_TABLES WHERE NAME LIKE '%#sql%';
+----------+--------------------+------+--------+-------+-------------+------------+---------------+------------+
| TABLE_ID | NAME               | FLAG | N_COLS | SPACE | FILE_FORMAT | ROW_FORMAT | ZIP_PAGE_SIZE | SPACE_TYPE |
+----------+--------------------+------+--------+-------+-------------+------------+---------------+------------+
|       64 | tmp/#sql3c316e_2_0 |    1 |      4 |    46 | Antelope    | Compact    |             0 | Single     |
+----------+--------------------+------+--------+-------+-------------+------------+---------------+------------+
1 row in set (0.00 sec)

mysql [localhost:5741] {msandbox} ((none)) > select * from information_schema.innodb_sys_datafiles where path like '%#sql%';
+-------+-------------------------------------------------------------+
| SPACE | PATH                                                        |
+-------+-------------------------------------------------------------+
|    46 | /home/jinyou.ma/sandboxes/msb_5_6_43/tmp/#sql3c316e_2_0.ibd |
+-------+-------------------------------------------------------------+
1 row in set (0.00 sec)
```

## After the patch

> There is a message about removing the missing table in the mysql error log.
```
2024-01-24T03:29:47.553930Z 0 [ERROR] InnoDB: Could not find a valid tablespace file for `tmp/#sql3c316e_2_0`. Please refer to http://dev.mysql.com/doc/refman/5.7/en/innodb-troubleshooting-datadict.html for how to resolve the issue.
2024-01-24T03:29:47.553938Z 0 [Warning] InnoDB: Ignoring tablespace `tmp/#sql3c316e_2_0` because it could not be opened.
2024-01-24T03:29:47.553944Z 0 [Warning] InnoDB: Removing missing table `tmp/#sql3c316e_2_0` from InnoDB data dictionary.
```

> The mysql does not contain orphaned data file

```
mysql [localhost:5741] {msandbox} ((none)) > SELECT * FROM INFORMATION_SCHEMA.INNODB_SYS_TABLES WHERE NAME LIKE '%#sql%';
Empty set (0.00 sec)

mysql [localhost:5741] {msandbox} ((none)) > select * from information_schema.innodb_sys_datafiles where path like '%#sql%';
Empty set (0.00 sec)
```

