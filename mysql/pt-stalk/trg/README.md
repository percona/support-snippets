# Triggers to start pt-stalk

To configure it run:

```
#Adjust to your plugin name
PT_STALK_PLUGIN='pt-stalk-load.sh'
PTDEST=/tmp/pt/collected/`hostname`/
mkdir -p $PTDEST;
cd /tmp/pt;
wget percona.com/get/pt-stalk https://raw.githubusercontent.com/percona/support-snippets/mysql/pt-stalk/trg/$PT_STALK_PLUGIN;
chmod +x pt*;
sudo ./pt-stalk --daemonize --dest=$PTDEST --pid=/tmp/pt/stalk.pid --log=/tmp/pt/stalk.log --function=/tmp/pt/$PT_STALK_PLUGIN --threshold=2 --iterations=2 --sleep=30 -- --user=root --password=''
```
