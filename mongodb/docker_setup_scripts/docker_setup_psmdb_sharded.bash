# local psmdb docker sharded cluster
case_number=CS000TEST
base_dir="/bigdisk/${case_number}"
docker_base_dir="${base_dir}/docker"

psmdb_version="7.0.28"
replica_count=3
shard_count=3

net_name="${case_number}-net"
net_prefix="172.2.0"

port_counter=0
psmdb_port=29017
mongos_port=28017

# cleanup => errors are expected if the containers are not running or there are other containers using the network
for i in $( seq 1 ${replica_count} ); do
  docker rm -f psmdb_${case_number}_config_${i}
  for j in $( seq 1 ${shard_count} ); do
    docker rm -f psmdb_${case_number}_shard${j}_${i}
  done
done
docker rm -f psmdb_${case_number}_mongos_1
docker network rm ${net_name}
sudo rm -rf ${base_dir}

# define mongo binary
major_version=${psmdb_version::1}
echo "major_version: ${major_version}"
mongo_binary="mongosh"
if [[ "${major_version}" == "3" || "${major_version}" == "4" || "${major_version}" == "5" ]]; then
  mongo_binary="mongo"
fi
echo "mongo_binary: ${mongo_binary}"

# initialize folders
for i in $( seq 1 ${replica_count} ); do
  mkdir -pv ${docker_base_dir}/psmdb_${case_number}_config_${i}/{data,log,scripts}
  for j in $( seq 1 ${shard_count} ); do
    mkdir -pv ${docker_base_dir}/psmdb_${case_number}_shard${j}_${i}/{data,log,scripts}
  done
done
mkdir -pv ${docker_base_dir}/psmdb_${case_number}_mongos_1/{data,log,scripts}

# copy keyfile
openssl rand -base64 741 > ${docker_base_dir}/keyfile
for i in $( seq 1 ${replica_count} ); do
  cp -v ${docker_base_dir}/keyfile ${docker_base_dir}/psmdb_${case_number}_config_${i}/
  for j in $( seq 1 ${shard_count} ); do
    cp -v ${docker_base_dir}/keyfile ${docker_base_dir}/psmdb_${case_number}_shard${j}_${i}/
  done
done
cp -v ${docker_base_dir}/keyfile ${docker_base_dir}/psmdb_${case_number}_mongos_1/

# set permissions
sudo chmod -vR 400 ${docker_base_dir}/psmdb_${case_number}_*/keyfile
sudo chmod -vR 755 ${docker_base_dir}/psmdb_${case_number}_*/{data,log,scripts}

# build mongod.conf
for i in $( seq 1 ${replica_count} ); do
  shard_name="config"
  cat > ${docker_base_dir}/psmdb_${case_number}_${shard_name}_${i}/mongod.conf << EOF
systemLog:
  destination: file
  logAppend: true
  path: /mongodb/log/mongod.log
  # verbosity: 3

net:
  bindIp: 0.0.0.0
  port: 27017

storage:
  dbPath: /mongodb/data
  directoryPerDB: true

replication:
  replSetName: ${shard_name}-${case_number}

sharding:
  clusterRole: configsvr

security:
  keyFile: /mongodb/keyfile

setParameter:
  authenticationMechanisms: SCRAM-SHA-256
EOF
  for j in $( seq 1 ${shard_count} ); do
    shard_name="shard${j}"
    cat > ${docker_base_dir}/psmdb_${case_number}_${shard_name}_${i}/mongod.conf << EOF
systemLog:
  destination: file
  logAppend: true
  path: /mongodb/log/mongod.log
  # verbosity: 3

net:
  bindIp: 0.0.0.0
  port: 27017

storage:
  dbPath: /mongodb/data
  directoryPerDB: true

replication:
  replSetName: ${shard_name}-${case_number}

sharding:
  clusterRole: shardsvr

security:
  keyFile: /mongodb/keyfile

setParameter:
  authenticationMechanisms: SCRAM-SHA-256
EOF
  done
done
cat ${docker_base_dir}/psmdb_${case_number}_${shard_name}_${i}/mongod.conf
# check files - size should be around 370
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_*

# create docker network
docker network create ${net_name} --subnet "${net_prefix}.0/24"
# start containers
## config
for i in $( seq 1 ${replica_count} ); do
  docker run -d --name psmdb_${case_number}_config_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 2 ))" -v ${docker_base_dir}/psmdb_${case_number}_config_${i}:/mongodb -p $(( psmdb_port + port_counter )):27017 percona/percona-server-mongodb:${psmdb_version} --config /mongodb/mongod.conf
  let port_counter++
done
## shards
for j in $( seq 1 ${shard_count} ); do
  for i in $( seq 1 ${replica_count} ); do
    docker run -d --name psmdb_${case_number}_shard${j}_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 2 ))" -v ${docker_base_dir}/psmdb_${case_number}_shard${j}_${i}:/mongodb -p $(( psmdb_port + port_counter )):27017 percona/percona-server-mongodb:${psmdb_version} --config /mongodb/mongod.conf
    let port_counter++
  done
done
# wait for initialization, might need to execute more than once until all return results
## config
for i in $( seq 1 ${replica_count} ); do
  until sudo grep -q "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_config_${i}/log/mongod.log 2>/dev/null; do
    sleep 1
  done
  echo -n "psmdb_config_${i}: ";sudo grep "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_config_${i}/log/mongod.log
done
## shards
for j in $( seq 1 ${shard_count} ); do
  for i in $( seq 1 ${replica_count} ); do
    until sudo grep -q "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_shard${j}_${i}/log/mongod.log 2>/dev/null; do
      sleep 1
    done
    echo -n "psmdb_shard${j}_${i}: ";sudo grep "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_shard${j}_${i}/log/mongod.log
  done
done

# set and print IPs
## config
for i in $( seq 1 ${replica_count} ); do
  declare psmdb_ip_config_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psmdb_${case_number}_config_${i})
  varname=psmdb_ip_config_${i}
  echo "${varname}: "${!varname}
done
## shards
for j in $( seq 1 ${shard_count} ); do
  for i in $( seq 1 ${replica_count} ); do
    declare psmdb_ip_shard${j}_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psmdb_${case_number}_shard${j}_${i})
    varname=psmdb_ip_shard${j}_${i}
    echo "${varname}: "${!varname}
  done
  echo ""
done

# create and apply replica set config documents with decreasing priority
## config
instance_priority=${replica_count}
rs_document="{_id : 'config-${case_number}', members: ["
for i in $( seq 1 ${replica_count} ); do
  varname=psmdb_ip_config_${i}
  rs_document="${rs_document}{ _id: $(( i - 1 )), host: '${!varname}:27017', priority: $(( instance_priority * 100 )) },"
  let instance_priority--
done
rs_document=${rs_document::-1}"]}"
echo "config rs_document: "${rs_document}
## apply the document
echo -n "config: "; docker exec psmdb_${case_number}_config_1 ${mongo_binary} --quiet --eval "rs.initiate( ${rs_document} )" admin
## shards
for j in $( seq 1 ${shard_count} ); do
  ## create each document
  instance_priority=${replica_count}
  rs_document="{_id : 'shard${j}-${case_number}', members: ["
  for i in $( seq 1 ${replica_count} ); do
    varname=psmdb_ip_shard${j}_${i}
    rs_document="${rs_document}{ _id: $(( i - 1 )), host: '${!varname}:27017', priority: $(( instance_priority * 100 )) },"
    let instance_priority--
  done
  rs_document=${rs_document::-1}"]}"
  echo "shard${j} rs_document: "${rs_document}
  ## apply document
  echo -n "shard${j}: "; docker exec psmdb_${case_number}_shard${j}_1 ${mongo_binary} --quiet --eval "rs.initiate( ${rs_document} )" admin
done
# wait for primary
## config
until sudo grep -q "Transition to primary complete" ${docker_base_dir}/psmdb_${case_number}_config_1/log/mongod.log 2>/dev/null; do
  sleep 1
done
echo -n "psmdb_config_1: ";sudo grep "Transition to primary complete" ${docker_base_dir}/psmdb_${case_number}_config_1/log/mongod.log
## shards
for j in $( seq 1 ${shard_count} ); do
  until sudo grep -q "Transition to primary complete" ${docker_base_dir}/psmdb_${case_number}_shard${j}_1/log/mongod.log 2>/dev/null; do
    sleep 1
  done
  echo -n "psmdb_shard${j}_1: ";sudo grep "Transition to primary complete" ${docker_base_dir}/psmdb_${case_number}_shard${j}_1/log/mongod.log
done

# add shard user
## config
echo -n "config: "; docker exec psmdb_${case_number}_config_1 ${mongo_binary} --quiet --eval 'db.getSiblingDB("admin").createUser( { user: "rs_testuser", pwd: "testpwd", roles: [ { role: "root", db: "admin" }]})' admin
## shards
for j in $( seq 1 ${shard_count} ); do
  echo -n "shard${j}: "; docker exec psmdb_${case_number}_shard${j}_1 ${mongo_binary} --quiet --eval 'db.getSiblingDB("admin").createUser( { user: "rs_testuser", pwd: "testpwd", roles: [ { role: "root", db: "admin" }]})' admin
done

# test shard access
## config
echo -n "psmdb_config_1: "; docker exec psmdb_${case_number}_config_1 ${mongo_binary} --quiet --authenticationDatabase admin -u rs_testuser -p testpwd --eval 'rs.status().members.forEach(function(node_data) {print("name: " + node_data.name + ", stateStr: " + node_data.stateStr + ", optimeDate: " + node_data.optimeDate)})' admin
# shards
for j in $( seq 1 ${shard_count} ); do
  echo -n "psmdb_shard${j}_1: "; docker exec psmdb_${case_number}_shard${j}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u rs_testuser -p testpwd --eval 'rs.status().members.forEach(function(node_data) {print("name: " + node_data.name + ", stateStr: " + node_data.stateStr + ", optimeDate: " + node_data.optimeDate)})' admin
done

# config hosts list for mongos
config_hosts_list=""
for i in $( seq 1 ${replica_count} ); do
  varname=psmdb_ip_config_${i}
  config_hosts_list="${config_hosts_list}${!varname}:27017,"
done
config_hosts_list=${config_hosts_list::-1}
echo "config_hosts_list: ${config_hosts_list}"
# mongos.conf
sudo bash -c "cat > ${docker_base_dir}/psmdb_${case_number}_mongos_1/mongos.conf" << EOF
systemLog:
  destination: file
  logAppend: true
  path: /mongodb/log/mongos.log
  # verbosity: 3

net:
  bindIp: 0.0.0.0
  port: 28017

sharding:
   configDB: config-${case_number}/${config_hosts_list}

security:
  keyFile: /mongodb/keyfile

processManagement:
  fork: true
EOF
sudo cat ${docker_base_dir}/psmdb_${case_number}_mongos_1/mongos.conf
sudo chown -v 1001:1001 ${docker_base_dir}/psmdb_${case_number}_mongos_1/mongos.conf

# start mongod container for mongos - there is no mongos image
docker run -d --name psmdb_${case_number}_mongos_1 --network ${net_name} --ip "${net_prefix}.$(( port_counter + 2 ))" -v ${docker_base_dir}/psmdb_${case_number}_mongos_1:/mongodb -p ${mongos_port}:28017 percona/percona-server-mongodb:${psmdb_version}

# start mongos process inside mongod container
docker exec psmdb_${case_number}_mongos_1 mongos -f /mongodb/mongos.conf
## wait for initialization
until sudo grep -q "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log 2>/dev/null; do
  sleep 1
done
echo -n "psmdb_mongos_1: ";sudo grep "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log

# create cluster user
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 -u rs_testuser -p testpwd --eval 'db.getSiblingDB("admin").createUser( { user: "testuser", pwd: "testpwd", roles: [ { role: "root", db: "admin" }] })' admin
# test access
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationDatabase admin -u testuser -p testpwd --eval 'db.runCommand({ connectionStatus: 1 })' admin

# add shards
for j in $( seq 1 ${shard_count} ); do
  ## create host list
  shard_hosts_list=""
  for i in $( seq 1 ${replica_count} ); do
    varname=psmdb_ip_shard${j}_${i}
    shard_hosts_list="${shard_hosts_list}${!varname}:27017,"
  done
  shard_hosts_list=${shard_hosts_list::-1}
  echo "shard${j}_hosts_list: "${shard_hosts_list}
  ## add shard
  docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationDatabase admin -u testuser -p testpwd --eval "sh.addShard('shard${j}-${case_number}/${shard_hosts_list}')" admin
done
# check cluster
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationDatabase admin -u testuser -p testpwd --eval 'sh.status()' admin

# done

# extra
## set mongos ip variable for PMM and exporter tests
psmdb_ip_mongos_1=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psmdb_${case_number}_mongos_1)
echo "psmdb_ip_mongos_1: ${psmdb_ip_mongos_1}"

## check logs
sudo tail -50f ${docker_base_dir}/psmdb_${case_number}_config_1/log/mongod.log
sudo tail -50f ${docker_base_dir}/psmdb_${case_number}_shard1_1/log/mongod.log
sudo tail -50f ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log

## list containers
docker ps -a | grep ${case_number}

## if needed to restart => reverse order
for i in $( seq ${replica_count} -1 1  ); do
  docker restart psmdb_${case_number}_${i}
done

## if needed to stop
for i in $( seq 1 ${replica_count} ); do
  docker stop psmdb_${case_number}_${i}
done

## if needed to delete
for i in $( seq 1 ${replica_count} ); do
  docker rm psmdb_${case_number}_${i} --force
done
