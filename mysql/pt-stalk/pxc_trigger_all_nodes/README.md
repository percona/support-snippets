# test
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(50)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(50)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(50)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(20)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(15)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(5)" &
timeout 20 mysql -h127.0.0.1 -P49164 -umsandbox -pmsandbox -e "select sleep(5)" &
date; p=$$; j=$(ps --no-headers -o pid --ppid=${p} |wc -l); timeout 9 bash -c "while [[ "${j}" -gt 0 ]]; do { sleep 0.5; x=(eval 'ps --no-headers -o pid --ppid=${p} |wc -l'); echo 'PID ${p} has ${j} (${x}) jobs'; } done; echo $j";  date;

p=$$; date; timeout 15 bash -c "while [[ $(ps --no-headers -o pid --ppid=${p} |wc -l) -gt 3 ]]; do {  ps --no-headers -o pid --ppid=${p}|wc -l; sleep 0.5; } done;  ps --no-headers -o pid --ppid=${p} |wc -l"; date;


./pt-stalk  --host=127.0.0.1 --user=root --password=msandbox --function=./trg.sh --plugin=./plugin.sh --variable=PXC_Threads_running --threshold=25 --cycles=3 --interval=1 --iterations=10 --run-time=30 --sleep=90 --dest=./tmp --log=/var/log/pt-stalk.log --pid=./tmp/p.pid

sudo ./pt-stalk  --host=127.0.0.1 --port=49164 --user=root --password=msandbox --function=./trg.sh --plugin=./plugin.sh --variable=PXC_Threads_running --threshold=25 --cycles=3 --interval=1 --iterations=10 --run-time=30 --sleep=90 --dest=./tmp --log=/var/log/pt-stalk.log --pid=./tmp/p.pid


Now configure pt-stalk in daemon mode on all nodes using pt-stalk-threads-trigger.sh function and pt-stalk.perf.plugin plugin:
sudo ./pt-stalk --daemonize --variable=threads --function=/tmp/pt/pt-stalk-threads-trigger.sh --threshold=100 --cycles=3 --iterations=4 --sleep=30 --dest=/tmp/pt/collected/`hostname`/ --log=/tmp/pt/collected/`hostname`/pt-stalk.log --plugin=/tmp/pt/pt-stalk.perf.plugin -- --user=root --password=<mysql-root-password>;
