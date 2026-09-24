#!/bin/bash
# Runs once at container startup, after mysqld is up and the lab accounts
# exist. Use it to load fixture data, break the state the candidate must fix,
# create users, etc.
#
# This file is DELETED right after it runs, so its comments never leak the
# answer. Anything you background here keeps running.
set -e

mysql -uroot <<'SQL'
-- Example: seed data.
-- CREATE DATABASE IF NOT EXISTS demo;
-- CREATE TABLE demo.widgets (id INT PRIMARY KEY, name VARCHAR(32));
SQL
