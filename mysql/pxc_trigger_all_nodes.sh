Please modify below snippet accordingly to connection properties for node 127 (replace -h IP_node127 and -ppass)
Please save below snippet to a file called /tmp/pt/pt-stalk-trigger.sh

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

timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(50)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(50)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(50)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(20)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(15)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(5)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(5)" &
date; p=$$; j=$(ps --no-headers -o pid --ppid=${p} |wc -l); timeout 9 bash -c "while [[ "${j}" -gt 0 ]]; do { sleep 0.5; x=(eval 'ps --no-headers -o pid --ppid=${p} |wc -l'); echo 'PID ${p} has ${j} (${x}) jobs'; } done; echo $j";  date;

p=$$; date; timeout 15 bash -c "while [[ $(ps --no-headers -o pid --ppid=${p} |wc -l) -gt 3 ]]; do {  ps --no-headers -o pid --ppid=${p}|wc -l; sleep 0.5; } done;  ps --no-headers -o pid --ppid=${p} |wc -l"; date;


Please save below snippet to a file called /tmp/pt/pt-stalk.perf.plugin and run chmod +x /tmp/pt/*.
#!/bin/bash
function before_collect() {
}

function after_collect() {
  local mysqld_pid_file=$(mysql ${EXT_ARGV} -BNe "SELECT @@global.pid_file"|awk '{print $2}');
  local mysqld_pid=$(cat ${mysqld_pid_file});
  (perf record -a -g -F99 -p ${mysqld_pid} -o ${OPT_DEST}/${prefix}-perf.data -- sleep 30);
  perf report -i ${OPT_DEST}/${prefix}-perf.data > ${OPT_DEST}/${prefix}-perf.report.out;
  perf script -i ${OPT_DEST}/${prefix}-perf.data > ${OPT_DEST}/${prefix}-perf.script.out;
}

./pt-stalk  --host=127.0.0.1 --user=root --password=msandbox --function=./trg.sh --plugin=./plugin.sh --variable=PXC_Threads_running --threshold=25 --cycles=3 --interval=1 --iterations=10 --run-time=30 --sleep=90 --dest=./tmp --log=/var/log/pt-stalk.log --pid=./tmp/p.pid

sudo ./pt-stalk  --host=127.0.0.1 --port=49164 --user=root --password=msandbox --function=./trg.sh --plugin=./plugin.sh --variable=PXC_Threads_running --threshold=25 --cycles=3 --interval=1 --iterations=10 --run-time=30 --sleep=90 --dest=./tmp --log=/var/log/pt-stalk.log --pid=./tmp/p.pid


Now configure pt-stalk in daemon mode on all nodes using pt-stalk-threads-trigger.sh function and pt-stalk.perf.plugin plugin:
sudo ./pt-stalk --daemonize --variable=threads --function=/tmp/pt/pt-stalk-threads-trigger.sh --threshold=100 --cycles=3 --iterations=4 --sleep=30 --dest=/tmp/pt/collected/`hostname`/ --log=/tmp/pt/collected/`hostname`/pt-stalk.log --plugin=/tmp/pt/pt-stalk.perf.plugin -- --user=root --password=<mysql-root-password>;
