# Simple binlog parser

This program will parse the output of `mysqlbinlog -v -v -v [binlog name]` and will match a DML against a specific string.
If it finds the string, it prints the Timestamp and DML.

## Compile

```
g++ -std=gnu++0x -o binlog_parser binlog_parser.cc
```

## Usage

```
./binlog_parser --file=binlog.00001 --match=277302549700124
#190404 13:19:22 server id 172784424  end_log_pos 4173378 	Write_rows: table id 924 flags: STMT_END_F
### INSERT INTO `test`.`tb1`
### SET
###   @1=277302549700124 /* LONGINT meta=0 nullable=0 is_null=0 */
###   @2=1554383962 /* TIMESTAMP(0) meta=0 nullable=0 is_null=0 */
###   @3=1554383962 /* TIMESTAMP(0) meta=0 nullable=0 is_null=0 */
###   @4=1 /* TINYINT meta=0 nullable=0 is_null=0 */
```