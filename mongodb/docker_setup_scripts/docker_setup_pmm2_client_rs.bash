# https://docs.percona.com/percona-monitoring-and-management/2/setting-up/client/index.html#docker
# docker PMM client setup

# create MongoDB containers
# ./docker_setup_psmdb_rs.bash
# ./docker_setup_psmdb_sharded.bash
# ./docker_setup_psmdb_single.bash

# create PMM server container
# ./docker_setup_pmm2_server.bash

# reuse variables from previous scripts
pmm_client_version="2.44.1"
client_ip="${net_prefix}.98"

# cleanup
docker rm -f pmm-client-data-${case_number} pmm-client-${case_number}
docker network rm ${net_name}

# crate data volume
docker create --volume /srv --name pmm-client-data-${case_number} percona/pmm-client:${pmm_client_version} /bin/true

# run client container with nohup to run in background and collect the logs
nohup docker run --rm \
--name pmm-client-${case_number} \
-e PMM_AGENT_SERVER_ADDRESS=${server_ip}:443 \
-e PMM_AGENT_SERVER_USERNAME=admin \
-e PMM_AGENT_SERVER_PASSWORD=${case_number} \
-e PMM_AGENT_SERVER_INSECURE_TLS=1 \
-e PMM_AGENT_SETUP=1 \
-e PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml \
--volumes-from pmm-client-data-${case_number} \
--network ${net_name} --ip ${client_ip} \
percona/pmm-client:${pmm_client_version} > ${docker_base_dir}/pmm-client.log &
tail -F ${docker_base_dir}/pmm-client.log

# check client status
docker exec pmm-client-${case_number} pmm-admin status

# configure authentication for MongoDB
## https://docs.percona.com/percona-monitoring-and-management/2/setting-up/client/mongodb.html#create-pmm-account-and-set-permissions
## create roles
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createRole({ "role": "explainRole", "privileges": [ { "resource": { "db": "", "collection": "" }, "actions": [ "collStats", "dbHash", "dbStats", "find", "listIndexes", "listCollections", "indexStats" ] }, { "resource": { "db": "", "collection": "system.profile" }, "actions": [ "dbStats", "collStats", "indexStats" ] }, { "resource": { "db": "", "collection": "system.version" }, "actions": [ "find" ] } ], "roles": [] })'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createRole({ "role": "pbmAnyAction", "privileges": [{ "resource": { "anyResource": true }, "actions": [ "anyAction" ] }], "roles": [] });'
## create user
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createUser({ user: "pmm", pwd: "pmm", roles: [ { role: "explainRole", db: "admin" }, { role: "clusterMonitor", db: "admin" }, { role: "read", db: "local" }, { "db" : "admin", "role" : "readWrite", "collection": "" }, { "db" : "admin", "role" : "backup" }, { "db" : "admin", "role" : "clusterMonitor" }, { "db" : "admin", "role" : "restore" }, { "db" : "admin", "role" : "pbmAnyAction" } ] })'
## check user
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").getUser("pmm")'

# add services
psmdb_port=28017
port_counter=0
for i in $( seq 1 ${replica_count} ); do
  varname=psmdb_ip_${i}
  docker exec pmm-client-${case_number} pmm-admin add mongodb --username=pmm --password=pmm --service-name=mongo_$(( psmdb_port + port_counter )) --environment=env-${case_number} --cluster=cl-${case_number} --host=${!varname} --port=27017 --enable-all-collectors
  let port_counter++
done

# done

# extra
# check client status again
docker exec pmm-client-${case_number} pmm-admin status
docker exec pmm-client-${case_number} pmm-admin list

# summary
docker exec pmm-client-${case_number} pmm-admin summary
docker exec pmm-client-${case_number} ls /usr/local/percona/pmm
docker cp pmm-client-${case_number}:/usr/local/percona/pmm/summary_89151ae04702_2025_10_27_16_05_21.zip ${docker_base_dir}/

## remove services
docker exec pmm-client-${case_number} pmm-admin remove mongodb mongo_28017
docker exec pmm-client-${case_number} pmm-admin remove mongodb mongo_28018
docker exec pmm-client-${case_number} pmm-admin remove mongodb mongo_28019

# list containers
docker ps -a | grep ${case_number}
