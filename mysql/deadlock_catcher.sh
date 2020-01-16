#!/bin/bash

# Configure mysql user and password
MYSQL="mysql -u root -psekret"

# get log location
error_log=$($MYSQL -BNe "SELECT @@global.log_error");

# set innodb_print_all_deadlocks;
$MYSQL -ve "SET GLOBAL innodb_print_all_deadlocks=1";

# verify instrumentation and consumers are properly setup
bad_instruments=$($MYSQL -BNe "SELECT COUNT(*) FROM performance_schema.setup_instruments WHERE ENABLED='NO' OR TIMED='NO' AND NAME LIKE 'statement/%'");
bad_consumers=$($MYSQL -BNe "SELECT COUNT(*) FROM performance_schema.setup_consumers WHERE ENABLED='NO' AND NAME LIKE 'events_statements%'");

# We might actually abort and let the user decide if they want to enable instrumentation,
# as it can have some impact on workload performance
if [[ "${bad_instruments}" -gt "0" ]]; then {
  echo "Need to enable all statement/ instruments in performance schema, write YES to continue";
  read prompt
  if [[ "${prompt}" -eq "YES" ]]; then {
    $MYSQL -ve "UPDATE performance_schema.setup_instruments SET ENABLED = 'YES', timed = 'YES' WHERE NAME LIKE 'statement/%'";
  } fi;
} fi;

if [[ "${bad_consumers}" -gt "0" ]]; then {
  echo "Need to enable all event_statements/ consumers, write YES to continue";
  read prompt
  if [[ "${prompt}" -eq "YES" ]]; then {
    $MYSQL -ve "UPDATE performance_schema.setup_consumers SET ENABLED = 'YES' WHERE NAME LIKE 'events_statements%'";
  } fi;
} fi;


offset=0; # offset lines in log (for logs with existing deadlock info)

tail -n +${offset} -f ${error_log} |stdbuf -o0 grep -n "[Tt]ransactions deadlock detected" |while read l; do {
  # $l is the first line of a printed deadlock
  start_line=$(cut -d':' -f1 <<< $l);
  # start_line is the line number of printed deadlock
  start_line=$((offset+start_line));

  # Now we need to find MySQL thread id (process_id from threads) and print queries for that session
  tail -n +$((start_line+1)) ${error_log} | head -n 17 | egrep "^MySQL thread id\ [0-9]{1,}" | awk '{print $4}' | tr ',' ' ' | while read process_id; do {
    #debug
    #echo $process_id

    $MYSQL -BNe "SELECT ev.thread_id, ev.EVENT_ID, ev.END_EVENT_ID, ev.EVENT_NAME, ev.SQL_TEXT FROM performance_schema.events_statements_history ev, performance_schema.threads t WHERE t.PROCESSLIST_ID = ${process_id} AND t.thread_id = ev.thread_id ORDER BY EVENT_ID DESC; "
  } done;
} done;
