#!/bin/bash
function trg_plugin() {
  local pxc_hosts="127.0.0.1 10.0.1.2 10.0.1.3x";
  local tmp_data="/tmp/pt-stalk.trg.dat";
  local tmp_log="/tmp/pt-stalk.trg.log";
  rm -f "${tmp_data}";
  for h in ${pxc_hosts}; do {
    mysql "${EXT_ARGV}" -h"${h}" -BNe "SHOW GLOBAL STATUS LIKE 'Threads_running'"  1>>"${tmp_data}"  2>>"${tmp_log}" &
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
