# Triggers to start pt-stalk

To configure it run:

```
# pt-stalk-flow-control-rate.sh
# Adjust threshold to make pt-stalk trigger when it reaches this value
PT_STALK_PLUGIN='pt-stalk-flow-control-rate.sh'
PTDEST=/tmp/pt/collected/`hostname`/
mkdir -p $PTDEST;
cd /tmp/pt;
wget percona.com/get/pt-stalk https://raw.githubusercontent.com/percona/support-snippets/master/mysql/pt-stalk/trg/$PT_STALK_PLUGIN;
chmod +x pt*;
sudo ./pt-stalk --daemonize --dest=$PTDEST --pid=/tmp/pt/stalk.pid --log=/tmp/pt/stalk.log --function=/tmp/pt/$PT_STALK_PLUGIN --variable='wsrep_flow_control_paused_ns' --threshold=100 --iterations=2 --sleep=30 -- --user=root --password=''

#Adjust to your plugin name
PT_STALK_PLUGIN='pt-stalk-load.sh'
PTDEST=/tmp/pt/collected/`hostname`/
mkdir -p $PTDEST;
cd /tmp/pt;
wget percona.com/get/pt-stalk https://raw.githubusercontent.com/percona/support-snippets/master/mysql/pt-stalk/trg/$PT_STALK_PLUGIN;
chmod +x pt*;
sudo ./pt-stalk --daemonize --dest=$PTDEST --pid=/tmp/pt/stalk.pid --log=/tmp/pt/stalk.log --function=/tmp/pt/$PT_STALK_PLUGIN --threshold=2 --iterations=2 --sleep=30 -- --user=root --password=''

# pt-stalk-seconds-behind-master.sh
# Adjust threshold to make pt-stalk trigger when it reaches this value
PT_STALK_PLUGIN='pt-stalk-seconds-behind-master.sh'
PTDEST=/tmp/pt/collected/`hostname`/
mkdir -p $PTDEST;
cd /tmp/pt;
wget percona.com/get/pt-stalk https://raw.githubusercontent.com/percona/support-snippets/master/mysql/pt-stalk/trg/$PT_STALK_PLUGIN;
chmod +x pt*;
sudo ./pt-stalk --daemonize --dest=$PTDEST --pid=/tmp/pt/stalk.pid --log=/tmp/pt/stalk.log --function=/tmp/pt/$PT_STALK_PLUGIN --variable='Seconds_Behind_Master' --threshold=30 --iterations=2 --sleep=30 -- --user=root --password=''
```
