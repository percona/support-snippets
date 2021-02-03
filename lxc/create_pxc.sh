#!/bin/bash
# Dispay script usage details
usage () {
  echo "Usage: [ options ]"
  echo "Options:"
  echo "--name=                         Identifier of this machine. Machines are identified by [user.name]-[type]-[name]"
  echo "--number-of-nodes=N             Number of nodes when running with pxc"
  echo "--version=                      Which specific version should be deployed"
  echo "--with-rr=PATH_TO_BINARY	Run mysqld under rr(Record and Replay)"
  echo "--help                          print usage"
}
# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=edv --longoptions=number-of-nodes:,name:,version:,with-rr:,help --name="$(realpath "$0")" -- "$@")"
  test $? -eq 0 || exit 1
  eval set -- "$go_out"
fi

if [[ $go_out == " --" ]];then
  usage
  exit 1
fi

for arg
do
  case "$arg" in
    -- ) shift; break;;
    --name )
    NAME="$2"
    shift 2
    ;;
    --number-of-nodes )
    NUMBER_OF_NODES="$2"
    shift 2
    ;;
    --version )
    VERSION=$2
    shift 2
    ;;
    --with-rr)
    WITH_RR=$2
    shift 2
    ;;
    --help )
    usage
    exit 0
    ;;
  esac
done
for (( i=1; i<=$NUMBER_OF_NODES; i++ ))do
    NODE_NAME="$NAME-$i"
    lxc init centos-7 $NODE_NAME -s $(whoami)
    lxc config set $NODE_NAME security.privileged true
    lxc start $NODE_NAME
    for (( c=1; c<=20; c++ ))do
        NODE_IP=$(lxc exec $NODE_NAME -- ip addr | grep inet | grep eth0 | awk '{print $2}' | awk -F'/' '{print $1}')
        #echo "NODEIP: $NODE_IP"
        if [[ -n $NODE_IP ]] ; then
            break;
        fi
        sleep 1
    done
    lxc exec $NODE_NAME -- yum -y install sudo https://repo.percona.com/yum/percona-release-latest.noarch.rpm
    if [[ ! -z "$VERSION" ]]; then
      VERSION_ACRONYM=$( echo ${VERSION} | sed 's/[^0-9]*//g' | head -c2);
      if [[ ${VERSION_ACRONYM} == "80" ]]
      then
        lxc exec $NODE_NAME -- percona-release setup pxc-80 
      fi
      lxc exec $NODE_NAME -- yum -y install tar gdb strace vim qpress socat wget less perf $VERSION

    else
      lxc exec $NODE_NAME -- yum -y install tar gdb strace vim qpress socat wget less perf Percona-XtraDB-Cluster-57
      VERSION_ACRONYM="57"
    fi
    lxc exec $NODE_NAME -- iptables -F
    lxc exec $NODE_NAME -- setenforce 0
    if [[ ${VERSION_ACRONYM} == "56" ]] || [[ ${VERSION_ACRONYM} == "55" ]]; then
        lxc exec $NODE_NAME -- mysql_install_db --user=mysql
    else
        lxc exec $NODE_NAME -- mysqld --initialize-insecure --user=mysql
    fi
    if [[ ! -z $IPS ]] ; then
        IPS="$IPS,$NODE_IP"
    else
        IPS="$NODE_IP"
    fi

    if [[ ! -z "$WITH_RR" ]] && [[ ${VERSION_ACRONYM} == "80" ]] ; then
       lxc exec $NODE_NAME -- yum -y install epel-release
       lxc exec $NODE_NAME -- yum -y install capnproto-libs percona-xtradb-cluster-debuginfo.x86_64
       lxc file push ${WITH_RR} ${NODE_NAME}/tmp/rr.tar
       lxc exec $NODE_NAME -- tar -xf /tmp/rr.tar -C /usr/
    fi
done

PXCSSL=""
SSTAUTH="wsrep_sst_auth=root:sekret"
TIMEOUTS=""
SST_TIMEOUT=""
SOCK_OPTS=""
if [[ ! -z "$WITH_RR" ]] && [[ ${VERSION_ACRONYM} == "80" ]] ; then
TIMEOUTS="evs.inactive_check_period=PT2.5S; evs.suspect_timeout=PT15S; gmcast.peer_timeout=PT9S"
SST_TIMEOUT="sst-initial-timeout=600"
SOCK_OPTS="sockopt=retry=600"
fi
if [[ ${VERSION_ACRONYM} == "80" ]]
then
  PXCSSL="pxc_encrypt_cluster_traffic = OFF"
  SSTAUTH=""
fi
for (( i=1; i<=$NUMBER_OF_NODES; i++ ))do
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
wsrep_provider_options              = \"gcs.fc_limit=500; gcs.fc_master_slave=YES; gcs.fc_factor=1.0; gcache.size=12M; gcache.page_size=12M; ${TIMEOUTS}\"
wsrep_slave_threads = 1
wsrep_auto_increment_control        = ON

wsrep_sst_method=xtrabackup-v2
$SSTAUTH

wsrep_cluster_address=gcomm://$IPS
wsrep_node_address=$NODE_IP
wsrep_node_name=node$i


innodb_file_per_table=1
innodb-log-file-size = 256M
innodb-flush-log-at-trx-commit = 2
innodb-buffer-pool-size = 512M

server_id=$i
binlog_format = ROW
$PXCSSL


[sst]
streamfmt=xbstream
${SST_TIMEOUT}
${SOCK_OPTS}

[xtrabackup]
compress
parallel=2
compress-threads=2
rebuild-threads=2
EOF"

if [[ $i -eq 1 ]]
then
    lxc exec $NODE_NAME -- systemctl start mysql@bootstrap
    if [[ $VERSION_ACRONYM == "80" ]]; then #Mysql 8 does not support GRANT with IDENTIFIED
        lxc exec $NODE_NAME -- mysql -e "CREATE USER 'root'@'%' IDENTIFIED BY 'sekret';"
        lxc exec $NODE_NAME -- mysql -e "SET PASSWORD FOR 'root'@'%' = 'sekret';"
        lxc exec $NODE_NAME -- mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%';"
        lxc exec $NODE_NAME -- mysql -e "CREATE USER 'root'@'127.0.0.1' IDENTIFIED BY 'sekret';"
        lxc exec $NODE_NAME -- mysql -e "SET PASSWORD FOR 'root'@'127.0.0.1' = 'sekret';"
        lxc exec $NODE_NAME -- mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1';"
        lxc exec $NODE_NAME -- mysql -e "SET PASSWORD FOR 'root'@'localhost' = 'sekret';"
        if [[ ! -z "$WITH_RR" ]] ; then
         lxc exec $NODE_NAME -- systemctl stop mysql@bootstrap
         lxc exec $NODE_NAME -- /usr/local/bin/rr /usr/sbin/mysqld --wsrep-new-cluster --wsrep_start_position=00000000-0000-0000-0000-000000000000:-1 --log-error=/var/lib/mysql/error.log &
	fi
    else
      lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'%' identified by 'sekret';"
      lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'127.0.0.1' identified by 'sekret';"
      lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'localhost' identified by 'sekret';"
    fi
else
    if [[ ! -z "$WITH_RR" ]] && [[ ${VERSION_ACRONYM} == "80" ]] ; then
        lxc exec $NODE_NAME -- /usr/local/bin/rr /usr/sbin/mysqld --wsrep_start_position=00000000-0000-0000-0000-000000000000:-1 --log-error=/var/lib/mysql/error.log &
	sleep 30
    else
      lxc exec $NODE_NAME -- systemctl start mysql
    fi
fi
done


unset MY_USER
unset NAME
unset N_NODES
unset NODE_NAME
unset NODE_IP
unset IPS
