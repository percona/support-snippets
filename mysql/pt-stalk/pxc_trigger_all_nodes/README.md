# Trigger based on Threads_Running on all nodes

```
PTDEST=/tmp/pt/collected/`hostname`/
mkdir -p $PTDEST;
cd /tmp/pt;
wget percona.com/get/pt-stalk https://raw.githubusercontent.com/percona/support-snippets/master/mysql/pt-stalk/pxc_trigger_all_nodes/pt-stalk-trigger_threads_running.sh;
chmod +x pt*;
rm /tmp/pt-stalk.trg.hosts;
pt-stalk --host=127.0.0.1 --user=root --password=sekret --function=/tmp/pt/pt-stalk-trigger_threads_running.sh --variable=PXC_Threads_running --threshold=10 --iterations=2 --sleep=30 --dest=$PTDEST;
```

*To Test:*

On a separate node:

```
for i in {1..15}; do mysql -u root -psekret -e "SELECT SLEEP(10)" & done
```
