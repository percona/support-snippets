DROP DATABASE IF EXISTS test_ptosc_plugin_rename_fk;
CREATE DATABASE IF NOT EXISTS test_ptosc_plugin_rename_fk;


USE test_ptosc_plugin_rename_fk;
-- Remove the tables before creating them
DROP TABLE IF EXISTS `t4`;
DROP TABLE IF EXISTS `t3`;
DROP TABLE IF EXISTS `t2`;
DROP TABLE IF EXISTS `t1`;
DROP TABLE IF EXISTS `t5`;
DROP TABLE IF EXISTS `count3`;
DROP TABLE IF EXISTS `count2`;

-- Create the tables
CREATE TABLE `t1` (
  `id` int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  `s` varchar(100) DEFAULT NULL,
  `g` int NOT NULL,
  `k` int,
  `t` time NOT NULL
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

CREATE TABLE `t2` (
  `id` int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  `g` int NOT NULL,
  `t1_id` int REFERENCES `t1`(`id`),
  `t` timestamp NOT NULL DEFAULT NOW()
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

CREATE TABLE `t3` (
  `id` int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  `t1_id` int REFERENCES `t1`(`id`),
  `t2_id` int,
  `k` int,
  `t` timestamp NOT NULL DEFAULT NOW(),
  KEY `k_t1_id`(`t1_id`),
  CONSTRAINT `C_FK_t2_t3_id` FOREIGN KEY FK_t2_t3_id (t2_id) REFERENCES `t2`(`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

CREATE TABLE `t4` (
  `id` int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  `t1_id` int REFERENCES `t1`(`id`),
  `t2_id` int,
  `t3_id` int,
  `k` int,
  `t` timestamp NOT NULL DEFAULT NOW(),
  KEY `k_t1_id`(`t1_id`),
  CONSTRAINT `C_FK_t2_t4_id` FOREIGN KEY FK_t2_t4_id (t2_id) REFERENCES `t2`(`id`),
  FOREIGN KEY FK_t3_t4_id (t3_id) REFERENCES `t3`(`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

CREATE TABLE `t5` (
  `id` int NOT NULL PRIMARY KEY AUTO_INCREMENT,
  `g` int NOT NULL,
  `k` int,
  `t` timestamp NOT NULL DEFAULT now(),
  CONSTRAINT uk_t5_g UNIQUE (k)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

CREATE TABLE `count3` (
    i int PRIMARY KEY
);

CREATE TABLE `count2` (
    i int PRIMARY KEY
);

