# local psmdb docker multiple standalone
case_number=CS000TEST
base_dir="/bigdisk/${case_number}"
docker_base_dir="${base_dir}/docker"

psmdb_version="7.0.28"
replica_count=3

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
# set permissions
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

security:
  authorization: enabled

setParameter:
  authenticationMechanisms: SCRAM-SHA-256
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 286
ls -lart ${docker_base_dir}/*/mongod.conf

# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_*

# create docker network
docker network create ${net_name} --subnet "${net_prefix}.0/24"
# start container
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

# add user and test access
for i in $( seq 1 ${replica_count} ); do
  docker exec psmdb_${case_number}_${i} ${mongo_binary} --quiet --eval 'db.getSiblingDB("admin").createUser( { user: "testuser", pwd: "testpwd", roles: [ { role: "root", db: "admin" }]})'
  docker exec psmdb_${case_number}_${i} ${mongo_binary} --quiet --host localhost --authenticationDatabase admin -u testuser -p testpwd --eval "db.runCommand({ connectionStatus: 1 })" admin
done

## done

## extra
# check containers
docker ps | grep ${case_number}

# check logs
sudo tail -F ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log
