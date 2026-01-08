# local psmdb docker replica set
case_number=CS000TEST
base_dir="/bigdisk/${case_number}"
docker_base_dir="${base_dir}/docker"

psmdb_version="8.0.17"
replica_count=7

net_name="${case_number}-net"
net_prefix="172.2.0"

port_counter=0
psmdb_port=29017

# cleanup => errors are expected if the containers are not running or there are other containers using the network
for i in $( seq 1 ${replica_count} ); do
  docker rm -f psmdb_${case_number}_${i}
done
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
  mkdir -pv ${docker_base_dir}/psmdb_${case_number}_${i}/{data,log,scripts}
done

# copy keyfile
openssl rand -base64 741 > ${docker_base_dir}/keyfile
for i in $( seq 1 ${replica_count} ); do
  cp -v ${docker_base_dir}/keyfile ${docker_base_dir}/psmdb_${case_number}_${i}/
done

# set permissions
sudo chmod -vR 400 ${docker_base_dir}/psmdb_${case_number}_*/keyfile
sudo chmod -vR 755 ${docker_base_dir}/psmdb_${case_number}_*/{data,log,scripts}

# build mongod.conf
for i in $( seq 1 ${replica_count} ); do
cat > ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf << EOF
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
  replSetName: rs-${case_number}

security:
  keyFile: /mongodb/keyfile

setParameter:
  authenticationMechanisms: SCRAM-SHA-256
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 331
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_*

# create docker network
docker network create ${net_name} --subnet "${net_prefix}.0/24"
# start containers
for i in $( seq 1 ${replica_count} ); do
  docker run -d --name psmdb_${case_number}_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 2 ))" -v ${docker_base_dir}/psmdb_${case_number}_${i}:/mongodb -p $(( psmdb_port + port_counter )):27017 percona/percona-server-mongodb:${psmdb_version} --config /mongodb/mongod.conf
  let port_counter++
done
# wait for initialization
for i in $( seq 1 ${replica_count} ); do
  until sudo grep -q "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log 2>/dev/null; do
    sleep 1
  done
  echo -n "psmdb_${i}: ";sudo grep "Waiting for connections" ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log
done

# set and print IPs
for i in $( seq 1 ${replica_count} ); do
  declare psmdb_ip_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psmdb_${case_number}_${i})
  varname=psmdb_ip_${i}
  echo "${varname}: "${!varname}
done
# create an apply replica set config document with decreasing priority
instance_priority=${replica_count}
rs_document="{_id : 'rs-${case_number}', members: ["
for i in $( seq 1 ${replica_count} ); do
  varname=psmdb_ip_${i}
  rs_document="${rs_document}{ _id: $(( i - 1 )), host: '${!varname}:27017', priority: $(( instance_priority * 100 )) },"
  let instance_priority--
done
rs_document=${rs_document::-1}"]}"
echo "rs_document: "${rs_document}
## apply the document
echo -n "psmdb_1: "; docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --eval "rs.initiate( ${rs_document} )" admin
# wait for primary
until sudo grep -q "Transition to primary complete" ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log 2>/dev/null; do
  sleep 1
done
echo -n "psmdb_1: ";sudo grep "Transition to primary complete" ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

# add and test user + check replica set
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --eval 'db.getSiblingDB("admin").createUser( { user: "testuser", pwd: "testpwd", roles: [ { role: "root", db: "admin" }]})' admin
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'rs.status().members.forEach(function(node_data) {print("name: " + node_data.name + ", stateStr: " + node_data.stateStr + ", optimeDate: " + node_data.optimeDate)})' admin

# done

# extra

## check logs
sudo tail -F ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log

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
