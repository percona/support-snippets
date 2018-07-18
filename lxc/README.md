# LXC wrapper

This wrapper helps to quickly create lxc machines for testing purposes

## Pre Requirements
In order to use this wrapper, you must have a storage with the same name as your username. This wrapper uses `whoami` to find the correct storage.

```
lxc storage create marcelo.altmann dir source=/home/marcelo.altmann/lxc
```


## Usage
```
./deploy_lxc
Usage: [ options ]
Options:
--type=[pxc|proxysql|proxysql-pxc|
          standalone|replication]               Type of machine to deploy, currently support pxc, proxysql, proxysql-pxc, standalone and replication
--name=						Identifier of this machine, such as #Issue Number. Machines are identified by [user.name]-[type]-[name]
						such as marcelo.altmann-pxc-xxxxxx
--proxysql-nodes=N				Number of ProxySQL nodes
--proxysql-pxc-node=				Container name of one PXC node
--number-of-nodes=N				Number of nodes when running with pxc
--show-versions=MAJOR_RELEASE			Used in combination with --type, this option shows the available versions to be installed
                                                Example --type=standalone --show-versions=5.7
--version=FULL_VERSION				Full version you want to install, for example Percona-Server-server-57-5.7.21-20.1.el7.x86_64
--destroy-all					destroy all containers from running user
--list						list all containers from your user
--help						print usage
```


## Deploy lxc examples

### PXC Cluster

* Create a 3 node cluster

```
# Replace 999999 by the #ISSUE number you are working with
./deploy_lxc --type=pxc --name=999999
```

* Create a 5 node cluster

```
# Replace 999999 by the #ISSUE number you are working with
./deploy_lxc --type=pxc --name=999999 --number-of-nodes=5
```

* List PXC versions

```
./deploy_lxc --type=pxc --show-versions=5.7
```

Example output:

```
./deploy_lxc --type=pxc --show-versions=5.7
Percona-XtraDB-Cluster-56-5.6.20-25.7.888.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.12-26.16.1.rc1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.14-26.17.1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.16-27.19.1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.17-27.20.2.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.17-29.20.3.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.18-29.20.1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.19-29.22.1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.19-29.22.3.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.20-29.24.1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.21-29.26.1.el7.x86_64
Percona-XtraDB-Cluster-57-5.7.22-29.26.1.el7.x86_64
```

* Create PXC on specific version

```
# Replace 999999 by the #ISSUE number you are working with
# Replace --version=Percona-XtraDB-Cluster-57-5.7.20-29.24.1.el7.x86_64 with the specific version you want to install
./deploy_lxc --type=pxc --name=232025 --version=Percona-XtraDB-Cluster-57-5.7.20-29.24.1.el7.x86_64
```



## LXC useful commands:

`lxc list` - List all lxc containers

`lxc exec <CONTAINER_NAME> /bin/bash` - Enter lxc container

`lxc image list images: | grep -i centos` - Gets a list of available images

`lxc image copy images:2dc2f6f3f58c local: --alias centos-7` - Copies a remote image to local storage

`lxc init centos-7 ≤CONTAINER_NAME> -s user.name` - Creates a new container

`lxc config set ≤CONTAINER_NAME> security.privileged true` - Set container to run as a privileged user

`lxc start ≤CONTAINER_NAME>` - Starts the container

`lxc stop ≤CONTAINER_NAME>` - Stops the container

`lxc delete ≤CONTAINER_NAME>` - Deletes the container
