#!/bin/bash
# Dispay script usage details
usage () {
  echo "Usage: [ options ]"
  echo "Options:"
  echo "--type=[pxc|proxysql|proxysql-pxc|
           standalone|replication] 			Type of machine to deploy, currently support pxc, proxysql, proxysql-pxc, standalone and replication"
  echo "--name=						Identifier of this machine, such as #Issue Number. Machines are identified by [user.name]-[type]-[name]"
  echo "						such as marcelo.altmann-pxc-xxxxxx"
  echo "--proxysql-nodes=N				Number of ProxySQL nodes"
  echo "--proxysql-pxc-node=				Container name of one PXC node"
  echo "--number-of-nodes=N				Number of nodes when running with pxc"
  echo "--destroy-all					destroy all containers from running user"
  echo "--help						print usage"
}

# Check if we have a functional getopt(1)
if ! getopt --test
  then
  go_out="$(getopt --options=edv --longoptions=type:,number-of-nodes:,name:,proxysql-nodes:,proxysql-pxc-node:,destroy-all,help --name="$(realpath "$0")" -- "$@")"
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
    --type )
      TYPE="$2"
      shift 2
      if [ "$TYPE" != "pxc" ] && 
         [ "$TYPE" != "proxysql" ] && 
         [ "$TYPE" != "proxysql-pxc" ] &&
         [ "$TYPE" != "replication" ] &&
         [ "$TYPE" != "standalone" ]; then
        echo "ERROR: Invalid --type passed" 
	echo " Curently only supported types: pxc, proxysql, proxysql-pxc, standalone"
        exit 1
      fi
    ;;
    --name )
    NAME="$2"
    shift 2
    ;;
    --number-of-nodes )
    NUMBER_OF_NODES="$2"
    shift 2
    ;;
    --proxysql-nodes )
    PROXY_NUMBER_OF_NODES="$2"
    shift 2
    ;;
    --proxysql-pxc-node )
    PROXY_PXC_NODE="$2"
    shift 2
    ;;
    --destroy-all )
    TYPE='destroy-all'
    shift
    ;;
    --help )
    usage
    exit 0
    ;;
  esac
done

#some standard vars
MY_USER=$(echo $(whoami) | sed 's/\./-/')


deploy_proxysql() {
  if [[ -z "$PROXY_NUMBER_OF_NODES" ]] ; then PROXY_NUMBER_OF_NODES=1; fi

  P_PROXY_PXC_NODE=""
  if [[ ! -z "$PROXY_PXC_NODE" ]] ; then 
    ./create_proxysql.sh --name="$MY_USER-$NAME-proxysql" --number-of-nodes=$PROXY_NUMBER_OF_NODES --pxc-node="$PROXY_PXC_NODE "
  else
    ./create_proxysql.sh --name="$MY_USER-$NAME-proxysql" --number-of-nodes=$PROXY_NUMBER_OF_NODES
  fi
}

deploy_pxc()
{
  if [[ -z "$NUMBER_OF_NODES" ]] ; then NUMBER_OF_NODES=3; fi

  if [[ -z "$NAME" ]] ; then NAME=""; fi
  M_NAME="$MY_USER-$NAME-pxc"
  echo "starting pxc"
  ./create_pxc.sh --name="$M_NAME" --number-of-nodes=$NUMBER_OF_NODES
}

deploy_standalone()
{
  if [[ -z "$NUMBER_OF_NODES" ]] ; then NUMBER_OF_NODES=1; fi
  if [[ -z "$NAME" ]] ; then NAME=""; fi
  if [[ -z "$M_NAME" ]] ; then M_NAME="$MY_USER-$NAME-standalone"; fi
  echo "starting standalone"
  ./create_standalone.sh --name="$M_NAME" --number-of-nodes=$NUMBER_OF_NODES
}
deploy_replication()
{
  if [[ -z "$NUMBER_OF_NODES" ]] ; then NUMBER_OF_NODES=2; fi
  if [[ -z "$NAME" ]] ; then NAME=""; fi
  if [[ -z "$M_NAME" ]] ; then M_NAME="$MY_USER-$NAME-replication"; fi

  echo "starting standalone"
  ./create_standalone.sh --name="$M_NAME" --number-of-nodes=$NUMBER_OF_NODES
  echo "starting replication"
  ./create_replication.sh --name="$M_NAME" --number-of-nodes=$NUMBER_OF_NODES 
}

if [ "$TYPE" == "pxc" ]; then deploy_pxc;
elif [ "$TYPE" == "proxysql" ]; then deploy_proxysql;
elif [ "$TYPE" == "standalone" ]; then deploy_standalone;
elif [ "$TYPE" == "replication" ]; then deploy_replication;
elif [ "$TYPE" == "proxysql-pxc" ]; then
  deploy_pxc
  PROXY_PXC_NODE="$MY_USER-$NAME-pxc-1"
  deploy_proxysql
elif [ "$TYPE" == "destroy-all" ]; then
  for c_name in $(lxc list -c n | grep $(whoami) | awk '{print $2}');
  do
    echo "destroying $c_name"
    lxc stop $c_name
    lxc	delete $c_name
  done
fi
