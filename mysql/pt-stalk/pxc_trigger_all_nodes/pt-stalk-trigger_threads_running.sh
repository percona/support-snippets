#!/bin/bash
function trg_plugin() {
  if [[ ! -f /tmp/pt-stalk.trg.hosts ]]; then
    echo "$(mysql ${EXT_ARGV} -BNe "SHOW GLOBAL STATUS LIKE 'wsrep_incoming_addresses'" | awk '{print $2}' | sed 's#,# #g')" > /tmp/pt-stalk.trg.hosts ;
  fi
  local tmp_data="/tmp/pt-stalk.trg.dat";
  local tmp_log="/tmp/pt-stalk.trg.log";
  rm -f "${tmp_data}";
  for h in $(cat /tmp/pt-stalk.trg.hosts); do {
    HOST="$(echo $h | awk -F':' '{print $1}')";
    PORT="$(echo $h | awk -F':' '{print $2}')";
    mysql ${EXT_ARGV} -h ${HOST} -P ${PORT} -BNe "SHOW GLOBAL STATUS LIKE 'Threads_running'"  1>>"${tmp_data}"  2>>"${tmp_log}" &
  } done;
  sleep 0.5;
  # if there are jobs still running or if there's no data collected...
  if [[ $(jobs -r|wc -l) -gt 0 || $(wc -l < "${tmp_data}") -lt 1 ]]; then {
    jobs -p|xargs kill -9; # terminate any process that might be still running
    echo 100000; # force collection if we failed to obtain data from one of the nodes;
  } else {
    awk '{print $2}' "${tmp_data}" | sort -nr | awk 'NR==1 {print $1}';
  } fi;
}
