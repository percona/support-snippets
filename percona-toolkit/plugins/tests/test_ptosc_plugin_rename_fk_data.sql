USE test_ptosc_plugin_rename_fk;

-- Populate the tables
INSERT INTO count3 VALUES (1), (2), (3);
INSERT INTO count2 VALUES (1), (2);

-- T1
INSERT INTO t1 VALUES (NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()));
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;
INSERT INTO t1 SELECT  NULL, uuid(), (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1;

-- T2
INSERT INTO t2 SELECT NULL, (FLOOR( 1 + RAND( ) *60 )) AS g, t1.id, now() FROM t1, count3 ORDER BY RAND();

-- T3
INSERT INTO t3 SELECT NULL, t1.id, t2.id, (FLOOR( 1 + RAND( ) *60 )), now() FROM t1 JOIN t2 ON t2.t1_id = t1.id, count3 ORDER BY RAND();

-- T4
INSERT INTO t4 SELECT NULL, t1_id, t2_id, id,  (FLOOR( 1 + RAND( ) *60 )), now() FROM t3, count2 ORDER BY RAND();

-- T5
INSERT INTO t5 VALUES (NULL, (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()));
INSERT INTO t5 SELECT  NULL, (FLOOR( 1 + RAND( ) *60 )), NULL, time(now()) FROM t1, count3 ORDER BY RAND();
UPDATE t5 SET k = id;
UPDATE t1 SET k = id;

