# https://docs.percona.com/percona-monitoring-and-management/2/setting-up/server/docker.html
# docker PMM server setup

# create MongoDB containers
# ./docker_setup_psmdb_rs.bash
# ./docker_setup_psmdb_sharded.bash
# ./docker_setup_psmdb_single.bash

# reuse variables from previous scripts
pmm_server_version="2.44.1"
server_ip="${net_prefix}.99"

# cleanup
docker rm -f pmm-server-${case_number} pmm-data-${case_number}
docker network rm ${net_name}

# pmm-server
docker create --volume /srv --name pmm-data-${case_number} percona/pmm-server:${pmm_server_version} /bin/true
docker run --detach --restart always --network ${net_name} --ip ${server_ip} --publish 4430:443 --volumes-from pmm-data-${case_number} --name pmm-server-${case_number} percona/pmm-server:${pmm_server_version}
## wait a bit until it all initializes
docker logs -f pmm-server-${case_number} 2>&1 | grep "exited: pmm-update-perform-init"

# change admin password
docker exec -t pmm-server-${case_number} change-admin-password ${case_number}

# tunneling
## another terminal
## the session will be open and then use https://localhost:8443 in local browser
server_ip="172.2.0.99"
ssh -L 8443:${server_ip}:443 support-highram.percona.com

## grafana password is the case number

# done

# extra
# pmm-dump
docker exec -ti --env case_number=${case_number} pmm-server-${case_number} bash
## export
pmm-dump export --pmm-url="https://admin:${case_number}@localhost:443" --allow-insecure-certs
## import
pmm-dump import --pmm-url="https://admin:${case_number}@localhost:443" --dump-path /tmp/pmm-dump-{CURRENT_TIMESTAMP}.tar.gz

# list containers
docker ps -a | grep ${case_number}
