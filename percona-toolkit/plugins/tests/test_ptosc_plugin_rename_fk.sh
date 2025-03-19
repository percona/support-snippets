#!/bin/bash
################################################################################
#####
##### Test file for plugin ptosc_plugin_rename_fk
#####   This is a very simple test file intented only to avoid repetitive tasks.
#####   It will probably be replaced for a real test suit in the future
################################################################################
MD5TOOL=`which md5sum`
MYSQL_CLI=`which mysql`
BASE_FOLDER=/opt/ptools
PLUGIN_NAME=ptosc_plugin_rename_fk
TEST_PREFIS="test_"

# MySQL configuration
TEST_DB_HOST=192.168.70.10
TEST_DB_PORT=3306
TEST_DB_USER=pxc_test_user
TEST_DB_PWD=123
TEST_DB_NAME=$TEST_PREFIS$PLUGIN_NAME
TEST_FOLDER=$BASE_FOLDER/tests
TEST_DB_FILE_SCHEMA=$TEST_FOLDER/$TEST_PREFIS$PLUGIN_NAME-schema.sql
TEST_DB_FILE_DATA=$TEST_FOLDER/$TEST_PREFIS$PLUGIN_NAME-data.sql
LOG_FILE=$TEST_FOLDER/ptosc_plugin_rename_fk.log
LOG_FILE_DB=$TEST_FOLDER/ptosc_plugin_rename_fk_db.log

# PT-OSC
PT_OSC=$BASE_FOLDER/pt-online-schema-change
PLUGIN_FILE=$BASE_FOLDER/plugins/$PLUGIN_NAME.pl

# Test utility
TEST_EXEC=0
TEST_PASSED=0
TEST_FAILED=0
# 
function error() {
    TEST_FAILED=$((TEST_FAILED + 1))
    echo -e "\e[1m\e[31m>> [FAILED] -> $@\e[0m"
}

function pass() {
    TEST_PASSED=$((TEST_PASSED + 1))
    echo -e "\e[1m\e[34m>> [PASSED] -> $@\e[0m"
}

function exec_ptosc() {
    local sql_command=$1
    local table_name=$2
    local extra_flags=$3
    local call="$PT_OSC --set-vars=foreign_key_checks=0 --no-check-alter --plugin=$PLUGIN_FILE --alter=\"$sql_command\" $extra_flags -h $TEST_DB_HOST -P $TEST_DB_PORT -u $TEST_DB_USER -p $TEST_DB_PWD D=$TEST_DB_NAME,t=$table_name --execute"
    
    echo -e "[[ $call ]]"
    RES=`eval "$call 2>&1 1>>$LOG_FILE"`
}

# Check if the MD5 matches with the create table
# @params :
#       - Table name 
#       - MD5 value
#       - Description
function check_md5() {
    local table_name=$1
    local test_number=$2
    TEST_EXEC=$((TEST_EXEC + 1))
    local test_file="$TEST_FOLDER/tmp_result-$TEST_EXEC.sql"
    local orig_file="$TEST_FOLDER/result_TEST-$test_number.sql"

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e "SHOW CREATE TABLE $table_name" 1> $test_file 2>>$LOG_FILE
    local md5_test=`$MD5TOOL $test_file | awk '{print $1}'`
    local md5_orig=`$MD5TOOL $orig_file | awk '{print $1}'`

    echo -e "Comparing files [$test_file] and [$orig_file]"
    if [ "$md5_test" != "$md5_orig" ]; then
        error "MD5 mimsmatch"
        echo -e "\e[1mDiff [diff $test_file $orig_file]: "
        diff $test_file $orig_file
        echo -e "\e[0m"
    else
        pass "MD5"
    fi
}

# Create database schema

function generate_md5_orig() {
    echo -e "Generating MD5 files...\n"
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e "ALTER TABLE t4 ADD COLUMN v varchar(100) NOT NULL DEFAULT ''" 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t4' > $TEST_FOLDER/result_TEST-01.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t4 DROP COLUMN k' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t4' > $TEST_FOLDER/result_TEST-02.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t4 CHANGE t t_date timestamp NOT NULL DEFAULT NOW()' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t4' > $TEST_FOLDER/result_TEST-03.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t3 CHANGE k g int not null default 0' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t3' > $TEST_FOLDER/result_TEST-04.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t1 ADD FOREIGN KEY (k) REFERENCES t5(k)' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t1' > $TEST_FOLDER/result_TEST-05.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t4 DROP FOREIGN KEY C_FK_t2_t4_id' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t4' > $TEST_FOLDER/result_TEST-06.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t2 ADD COLUMN k int, ADD FOREIGN KEY (k) REFERENCES t5(k)' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t2' > $TEST_FOLDER/result_TEST-07.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t2 DROP COLUMN t1_id' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t2' > $TEST_FOLDER/result_TEST-08.sql 2>>/dev/null

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD $TEST_DB_NAME -e 'ALTER TABLE t1 CHANGE k new_k int' 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t1' > $TEST_FOLDER/result_TEST-09.sql

    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER --raw -p$TEST_DB_PWD $TEST_DB_NAME -e 'SHOW CREATE TABLE t5' > $TEST_FOLDER/result_TEST-10.sql
}

function create_schema() {
    echo -e "Creating schema to generate MD5 files...\n"
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD < $TEST_DB_FILE_SCHEMA 2>&1 1>>$LOG_FILE_DB
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD < $TEST_DB_FILE_DATA 2>&1 1>>$LOG_FILE_DB
    generate_md5_orig

    echo -e "Re-creating the schema to start the tests...\n"
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD < $TEST_DB_FILE_SCHEMA 2>&1 1>>$LOG_FILE_DB

    echo -e "Populating the schema...\n"
    $MYSQL_CLI -h$TEST_DB_HOST -P$TEST_DB_PORT -u$TEST_DB_USER -p$TEST_DB_PWD < $TEST_DB_FILE_DATA 2>&1 1>>$LOG_FILE_DB
}

# Test
function test_01_add_col () {
    exec_ptosc "ADD COLUMN v varchar(100) NOT NULL DEFAULT ''" 't4'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't4' "01"
    fi
}

# Test
function test_02_drop_col () {
    exec_ptosc "DROP COLUMN k" 't4'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't4' 02
    fi
}

# Test
function test_03_rename_col () {
    exec_ptosc "CHANGE t t_date timestamp NOT NULL DEFAULT NOW()" 't4'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't4' 03
    fi
}

# Test
function test_04_rename_col_add_not_null_col_DROP_SWAP_METHOD () {
    exec_ptosc "CHANGE k g int not null default 0" 't3' "--alter-foreign-keys-method=drop_swap"

    if [ "$RES" != "" ]; then
        error $RES
    else
        # Check the changed table
        check_md5 't3' 04

        # Check the references
        check_md5 't4' 03
    fi
}

# Test
function test_05_add_fk () {
    exec_ptosc "ADD FOREIGN KEY (k) REFERENCES t5(k)" 't1'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't1' 05
    fi
}

# Test
function test_06_drop_fk () {
    exec_ptosc "DROP FOREIGN KEY _C_FK_t2_t4_id" 't4'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't4' 06
    fi
}

# Test
function test_07_add_col_fk_DROP_SWAP_METHOD () {
    exec_ptosc "ADD COLUMN k int, ADD FOREIGN KEY (k) REFERENCES t5(k)" 't2' "--alter-foreign-keys-method=drop_swap"

    if [ "$RES" != "" ]; then
        error $RES
    else
        # Check the changed table
        check_md5 't2' 07

        # check the references
        check_md5 't3' 04
        check_md5 't4' 06
    fi
}

# Test
function test_08_drop_col_fk_DROP_SWAP_METHOD () {
    exec_ptosc "DROP COLUMN t1_id" 't2' "--alter-foreign-keys-method=drop_swap"

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't2' 08
    fi
}

# Test
function test_09_rename_col_fk () {
    exec_ptosc "CHANGE k new_k int" 't1'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't1' 09
    fi
}

# Test
function test_10_drop_column_with_child () {
    exec_ptosc "DROP COLUMN k" 't5'

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't5' 10
        # check the references
        check_md5 't1' 09
        check_md5 't2' 08
    fi
}

# Test
function test_11_rename_col_add_not_null_col_REBUILD_CONSTRAINTS_METHOD () {
    exec_ptosc "CHANGE g k int not null default 0" 't3' "--alter-foreign-keys-method=rebuild_constraints"

    if [ "$RES" != "" ]; then
        error $RES
    else
        # Check the changed table
        check_md5 't3' 04

        # Check the references
        check_md5 't4' 03
    fi
}

# Test
function test_12_add_col_fk_REBUILD_CONSTRAINTS_METHOD () {
    exec_ptosc "ADD COLUMN k2 int, ADD FOREIGN KEY (k) REFERENCES t5(k)" 't2' "--alter-foreign-keys-method=rebuild_constraints"

    if [ "$RES" != "" ]; then
        error $RES
    else
        # Check the changed table
        check_md5 't2' 07

        # check the references
        check_md5 't3' 04
        check_md5 't4' 06
    fi
}

# Test
function test_13_drop_col_fk_REBUILD_CONSTRAINTS_METHOD () {
    exec_ptosc "DROP COLUMN k" 't2' "--alter-foreign-keys-method=rebuild_constraints"

    if [ "$RES" != "" ]; then
        error $RES
    else
        check_md5 't2' 08
    fi
}


#### Test Executor
function runUnitTests() {
    testNames=$(grep "^function test_" $0 | awk '{print $2}')
    testNamesArray=($testNames)
    echo -e "\n\e[1m\e[34m>>> Starting test cases...\e[0m\n"
    for testCase in "${testNamesArray[@]}"
    do
        :
        echo -e "\n>> \e[32m$testCase\n\e[0m"
        eval $testCase
    done
    echo -e "\n\n\e[1m\e[34m>>> RESULTS: \n"
    echo -e "\e[1m\e[31m>> [FAILED] -> $TEST_FAILED\e[0m"
    echo -e "\e[1m\e[34m>> [PASSED] -> $TEST_PASSED\e[0m"
}

create_schema
runUnitTests