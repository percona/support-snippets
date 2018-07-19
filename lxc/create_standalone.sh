#!/bin/bash
# Dispay script usage details
usage () {
  echo "Usage: [ options ]"
  echo "Options:"
  echo "--name=                         Identifier of this machine. Machines are identified by [user.name]-[type]-[name]"
  echo "--number-of-nodes=N             Number of nodes when running with pxc"
  echo "--version=                      Which specific version should be deployed"
  echo "--help                          print usage"
}

# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=edv --longoptions=number-of-nodes:,name:,version:,help --name="$(realpath "$0")" -- "$@")"
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
    --help )
    usage
    exit 0
    ;;
  esac
done

for (( i=1; i<=$NUMBER_OF_NODES; i++ ))do
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
    if [[ ! -z "$VERSION" ]]; then
      lxc exec $NODE_NAME -- yum -y install tar gdb strace vim qpress socat $VERSION
    else
      lxc exec $NODE_NAME -- yum -y install tar gdb strace vim qpress socat Percona-Server-server-57
    fi
    lxc exec $NODE_NAME -- iptables -F
    lxc exec $NODE_NAME -- setenforce 0
    lxc exec $NODE_NAME -- mysqld --initialize-insecure --user=mysql
    lxc exec $NODE_NAME -- systemctl start mysql
    lxc exec $NODE_NAME -- sh -c "cat << EOF > /etc/my.cnf
[mysqld]
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock

# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0

log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EOF"
    lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'%' identified by 'sekret';"
    lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'127.0.0.1' identified by 'sekret';"
    lxc exec $NODE_NAME -- mysql -e "grant all privileges on *.* to 'root'@'localhost' identified by 'sekret';"
done


unset MY_USER
unset NAME
unset N_NODES
unset NODE_NAME
unset NODE_IP
unset IPS
