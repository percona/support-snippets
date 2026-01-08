# PBM setup to run with docker replica set

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# if you plan to use minio:
# ./docker_setup_minio.bash

# reuse variables from previous scripts
pbm_version="2.12.0"
port_counter=0

# cleanup => errors are expected if the containers are not running or there are other containers using the network
for i in $( seq 1 ${replica_count} ); do
  docker rm -f pbm_${case_number}_${i}
done
sudo rm -rf ${docker_base_dir}/pbm_${case_number}
docker network rm ${net_name}

# setup PBM user
# https://docs.percona.com/percona-backup-mongodb/install/configure-authentication.html#create-the-pbm-user
## create role
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createRole({ "role": "pbmAnyAction","privileges": [{ "resource": { "anyResource": true },"actions": [ "anyAction" ]}],"roles": []});'
## create user
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createUser({user: "pbmuser","pwd": "secretpwd","roles" : [{ "db" : "admin", "role" : "readWrite", "collection": "" },{ "db" : "admin", "role" : "backup" },{ "db" : "admin", "role" : "clusterMonitor" },{ "db" : "admin", "role" : "restore" },{ "db" : "admin", "role" : "pbmAnyAction" }], mechanisms: ["SCRAM-SHA-256"]});'
## check
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").getUser("pbmuser")'

# create backup folder
mkdir -pv ${docker_base_dir}/pbm_${case_number}/backup
sudo chmod -v 755 ${docker_base_dir}/pbm_${case_number}/backup
sudo chown -vR 1001:1001 ${docker_base_dir}/pbm_${case_number}/backup

# get PSMDB IPs and launch PBM containers
for i in $( seq 1 ${replica_count} ); do
  varname=psmdb_ip_${i}
  docker run -d --name pbm_${case_number}_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 32 ))" -v ${docker_base_dir}/psmdb_${case_number}_${i}:/mongodb -v ${docker_base_dir}/pbm_${case_number}:/pbm_volume -e PBM_MONGODB_URI="mongodb://pbmuser:secretpwd@${!varname}:27017" percona/percona-backup-mongodb:${pbm_version}
  let port_counter++
done

# copy binaries for physical backups to local
mkdir -pv ${docker_base_dir}/bin
docker cp psmdb_${case_number}_1:/usr/bin/mongod ${docker_base_dir}/bin/
docker cp pbm_${case_number}_1:/usr/bin/pbm ${docker_base_dir}/bin/
docker cp pbm_${case_number}_1:/usr/bin/pbm-agent ${docker_base_dir}/bin/
docker cp pbm_${case_number}_1:/usr/bin/pbm-agent-entrypoint ${docker_base_dir}/bin/
docker cp pbm_${case_number}_1:/usr/bin/pbm-speed-test ${docker_base_dir}/bin/
# copy from local to containers
for i in $( seq 1 ${replica_count} ); do
  docker cp ${docker_base_dir}/bin/mongod pbm_${case_number}_${i}:/usr/bin/
  docker cp ${docker_base_dir}/bin/pbm psmdb_${case_number}_${i}:/usr/bin/
  docker cp ${docker_base_dir}/bin/pbm-agent psmdb_${case_number}_${i}:/usr/bin/
  docker cp ${docker_base_dir}/bin/pbm-agent-entrypoint psmdb_${case_number}_${i}:/usr/bin/
  docker cp ${docker_base_dir}/bin/pbm-speed-test psmdb_${case_number}_${i}:/usr/bin/
done

# create pbm_config.yaml
## comment in and out the storage type and metadata according to the necessity of the case
cat > ${docker_base_dir}/pbm_config.yaml <<EOF
pitr:
  enabled: true
  oplogSpanMin: 2
storage:
  # type: filesystem
  # filesystem:
  #   path: /pbm_volume/backup
  type: s3
  s3:
    endpointUrl: "http://${minio_ip}:9000"
    region: my-region
    bucket: pbm-backup
    credentials:
      access-key-id: ROOTNAME
      secret-access-key: CHANGEME123
  # type: gcs
  # gcs:
  #    bucket: ${case_number}-bucket
  #    prefix: cl-${case_number}
  #    credentials:
  #      hmacAccessKey: GOOG1XXXX
  #      hmacSecret: YYYY
backup:
  oplogSpanMin: 2
EOF
cat ${docker_base_dir}/pbm_config.yaml

# upload pbm_config.yaml
docker cp ${docker_base_dir}/pbm_config.yaml pbm_${case_number}_1:/tmp/pbm_config.yaml
# apply pbm_config.yaml
docker exec pbm_${case_number}_1 pbm config --file /tmp/pbm_config.yaml

# done

# extra
## check containers
docker ps | grep ${case_number}

## check logs
docker logs pbm_${case_number}_${i}

## get status
docker exec pbm_${case_number}_${i} pbm status

## run backup
docker exec pbm_${case_number}_${i} pbm backup -w

docker exec pbm_${case_number}_${i} pbm backup --type physical -w

## run restore
docker exec pbm_${case_number}_${i} pbm list

docker exec pbm_${case_number}_${i} pbm restore "2025-10-15T11:32:18Z"

docker exec pbm_${case_number}_${i} pbm describe-restore 2025-10-15T11:34:27.399523389Z

## force resync
docker exec pbm_${case_number}_${i} pbm config --force-resync

## if needed to restart
for i in $( seq 1 ${replica_count} ); do
  docker restart pbm_${case_number}_${i}
done
