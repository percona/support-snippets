#!/bin/bash
NAME="$1"
N_NODES=$2

for (( i=1; i<=$N_NODES; i++ ))do
    NODE_NAME="$NAME-$i"
    lxc init centos-7 $NODE_NAME -s $(whoami)
    lxc start $NODE_NAME
    for (( c=1; c<=20; c++ ))do
        NODE_IP=$(lxc exec $NODE_NAME -- ip addr | grep inet | grep eth0 | awk '{print $2}' | awk -F'/' '{print $1}')
        #echo "NODEIP: $NODE_IP"
        if [[ -n $NODE_IP ]] ; then
            break;
        fi
        sleep 1
    done
    lxc exec $NODE_NAME -- yum -y install http://www.percona.com/downloads/percona-release/redhat/0.1-6/percona-release-0.1-6.noarch.rpm
    lxc exec $NODE_NAME -- yum -y install tar gdb strace vim qpress socat Percona-XtraDB-Cluster-57
    lxc exec $NODE_NAME -- iptables -F
    lxc exec $NODE_NAME -- setenforce 0
    lxc exec $NODE_NAME -- mysqld --initialize-insecure --user=mysql
    if [[ ! -z $IPS ]] ; then
        IPS="$IPS,$NODE_IP"
    else
        IPS="$NODE_IP"
    fi
done


for (( i=1; i<=$N_NODES; i++ ))do
NODE_NAME="$NAME-$i"
NODE_IP=$(lxc exec $NODE_NAME -- ip addr | grep inet | grep eth0 | awk '{print $2}' | awk -F'/' '{print $1}')
lxc exec $NODE_NAME -- sh -c "cat << EOF > /etc/my.cnf
[mysql]
port                                = 3306
socket                              = /var/lib/mysql/mysql.sock
prompt='PXC: \u@\h (\d) > '

[client]
port                                = 3306
socket                              = /var/lib/mysql/mysql.sock


[mysqld]
socket                              = /var/lib/mysql/mysql.sock
datadir=/var/lib/mysql
user=mysql


wsrep_cluster_name=$NAME

wsrep_provider=/usr/lib64/libgalera_smm.so
wsrep_provider_options              = \"gcs.fc_limit=500; gcs.fc_master_slave=YES; gcs.fc_factor=1.0; gcache.size=256M;\"
wsrep_slave_threads = 1
wsrep_auto_increment_control        = ON

wsrep_sst_method=xtrabackup-v2
wsrep_sst_auth=root:sekret

wsrep_cluster_address=gcomm://$IPS
wsrep_node_address=$NODE_IP
wsrep_node_name=node$i


innodb_locks_unsafe_for_binlog=1
innodb_autoinc_lock_mode=2
innodb_file_per_table=1
innodb-log-file-size = 256M
innodb-flush-log-at-trx-commit = 2
innodb-buffer-pool-size = 512M
innodb_use_native_aio = 0

server_id=$i
binlog_format = ROW



[sst]
streamfmt=xbstream

[xtrabackup]
compress
parallel=2
compress-threads=2
rebuild-threads=2
EOF"

if [[ $i -eq 1 ]]
then
    lxc exec $NODE_NAME -- systemctl start mysql@bootstrap

    lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'%' identified by 'sekret';"
    lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'127.0.0.1' identified by 'sekret';"
    lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'localhost' identified by 'sekret';"
else
    lxc exec $NODE_NAME -- systemctl start mysql
fi
done


unset MY_USER
unset NAME
unset N_NODES
unset NODE_NAME
unset NODE_IP
unset IPS
