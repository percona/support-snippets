#!/bin/bash
# Dispay script usage details
usage () {
  echo "Usage: [ options ]"
  echo "Options:"
  echo "--name=                         Identifier of this machine. Machines are identified by [user.name]-[type]-[name]"
  echo "--number-of-nodes=N             Number of nodes when running with pxc"
  echo "--help                          print usage"
}

# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=edv --longoptions=number-of-nodes:,name:,help --name="$(realpath "$0")" -- "$@")"
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
    --help )
    usage
    exit 0
    ;;
  esac
done

for (( i=1; i<=$NUMBER_OF_NODES; i++ ))do
  NODE_NAME="$NAME-$i"
  NODE_IP=$(lxc exec $NODE_NAME -- ip addr | grep inet | grep eth0 | awk '{print $2}' | awk -F'/' '{print $1}')
  lxc exec $NODE_NAME -- sh -c "cat << EOF >> /etc/my.cnf
log-bin
server-id=$i
report_host=$NODE_IP
EOF"
  lxc exec $NODE_NAME -- systemctl restart mysql
  if [[ $i -eq "1" ]] ; then
    MASTER_IP=$NODE_IP
  else
    lxc exec $NODE_NAME -- mysql -u root -psekret -e "CHANGE MASTER TO MASTER_HOST='$MASTER_IP', MASTER_USER='root', MASTER_PASSWORD='sekret'; START SLAVE"
  fi
done


unset MY_USER
unset NAME
unset N_NODES
unset NODE_NAME
unset NODE_IP
unset MASTER_IP
