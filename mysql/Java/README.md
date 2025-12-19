# Simple Java MySQL connector test/benchmark script

This program will open a pool of MySQL connections and execute the queries provided in a smaller number of active threads. The test can be done in X rounds with specified pause.

## Compile

```
javac -cp .:/usr/share/java/mysql-connector-j-8.2.0.jar MySQLTester.java
```

## Usage

```
Usage: java MySQLTester <host> <user> <password> <port> <poolSize> <threadCount> <queriesInput> [<duration> [<executions> [<pause>]]]

For example:
$ java -cp .:/usr/share/java/mysql-connector-j-8.2.0.jar MySQLTester 192.168.10.10 myuser 'verysecurepassword' 3306 100 8 queries.sql 360 5 120
Loaded 8 queries.
Starting test run 1 of 5...
Test run 1 completed in 360.00 seconds.
Test run 1 queries executed: 2951962
Test run 1 throughput: 8199.83 QPS
Pausing for 120 seconds...
Starting test run 2 of 5...
...
```
