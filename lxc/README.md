# LXC wrapper

This wrapper helps to quickly create lxc machines for testing purposes

## Pre Requirements
In o`rder to use this wrapper, you must have a storage with the same name as your username. This wrapper uses `whoami` to find the correct storage.

```
lxc storage create marcelo.altmann dir source=/home/marcelo.altmann/lxc
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
