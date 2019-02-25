#!/bin/bash
# Dispay script usage details
usage () {
  echo "Usage: [ options ]"
  echo "Options:"
  echo "--name=				Identifier of this machine. Machines are identified by [user.name]-[type]-[name]"
  echo "--pxc-node=			Name of pxc node to connect to"
  echo "--replication-prefix=		Prefix of machines used for replication"
  echo "--number-of-nodes=N		Number of nodes when running with pxc"
  echo "--help				print usage"
}

# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=edv --longoptions=number-of-nodes:,name:,pxc-node:,replication-prefix:,help --name="$(realpath "$0")" -- "$@")"
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
    --pxc-node )
    PXC_NODE="$2"
    shift 2
    ;;
    --replication-prefix )
    REPLICATION_PREFIX="$2"
    shift 2
    ;;
    --help )
    usage
    exit 0
    ;;
  esac
done
    

if [[ -z "$NUMBER_OF_NODES" ]] ; then NUMBER_OF_NODES=1; fi
if [[ -z "$NAME" ]] ; 
then 
  echo "You need to specify a name"
  exit 1
fi
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
  lxc exec $NODE_NAME -- yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
  lxc exec $NODE_NAME -- yum -y install proxysql Percona-Server-client-57 which
  lxc exec $NODE_NAME -- systemctl start proxysql
  if [[ ! -z "$PXC_NODE" ]]; then
    PXC_IP=$(lxc exec $PXC_NODE -- ip addr | grep inet | grep eth0 | awk '{print $2}' | awk -F'/' '{print $1}')
    lxc exec $NODE_NAME -- sed "s/CLUSTER_HOSTNAME='localhost'/CLUSTER_HOSTNAME='$PXC_IP'/g" -i /etc/proxysql-admin.cnf
    lxc exec $NODE_NAME -- sed "s/CLUSTER_USERNAME='admin'/CLUSTER_USERNAME='root'/g" -i /etc/proxysql-admin.cnf
    lxc exec $NODE_NAME -- sed "s/CLUSTER_PASSWORD='admin'/CLUSTER_PASSWORD='sekret'/g" -i /etc/proxysql-admin.cnf
    lxc exec $NODE_NAME -- proxysql-admin --config-file=/etc/proxysql-admin.cnf --without-check-monitor-user --without-cluster-app-user --syncusers --enable
  elif [[ ! -z "$REPLICATION_PREFIX" ]]; then
    for node_ip in $( $(dirname "$0")/deploy_lxc --list | grep $REPLICATION_PREFIX | awk '{print $6}');
    do
       lxc exec $NODE_NAME -- mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "INSERT INTO mysql_servers (hostgroup_id, hostname) VALUES (11, '$node_ip');"
    done
    lxc exec $NODE_NAME -- mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup) VALUES (10, 11); LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"
    lxc exec $NODE_NAME -- mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "UPDATE global_variables SET variable_value='root' WHERE variable_name='mysql-monitor_username'"
    lxc exec $NODE_NAME -- mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "UPDATE global_variables SET variable_value='sekret' WHERE variable_name='mysql-monitor_password'"
    lxc exec $NODE_NAME -- mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK"
    lxc exec $NODE_NAME -- sed "s/CLUSTER_HOSTNAME='localhost'/CLUSTER_HOSTNAME='$node_ip'/g" -i /etc/proxysql-admin.cnf
    lxc exec $NODE_NAME -- sed "s/CLUSTER_USERNAME='admin'/CLUSTER_USERNAME='root'/g" -i /etc/proxysql-admin.cnf
    lxc exec $NODE_NAME -- sed "s/CLUSTER_PASSWORD='admin'/CLUSTER_PASSWORD='sekret'/g" -i /etc/proxysql-admin.cnf
    lxc exec $NODE_NAME -- proxysql-admin --config-file=/etc/proxysql-admin.cnf --syncusers
  fi
done
