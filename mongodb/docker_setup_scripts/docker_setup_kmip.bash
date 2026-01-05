# configures KMIP server for data-at-rest encryption for a replica set. TLS enabled between MongoDB and KMIP.
# https://github.com/altmannmarcelo/docker-kmip/
# https://pykmip.readthedocs.io/en/latest/server.html

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# create Base CA and certificates
## ./docker_setup_tls_base_certs.sh

# reuse variables from previous scripts

# cleanup
docker rm -f kmip_${case_number}
docker network rm ${net_name}

# start kmip container
docker run --rm -d --network ${net_name} --ip ${server_ip} --name kmip_${case_number} \
  --security-opt seccomp=unconfined \
  --cap-add=NET_ADMIN \
  -p 5696:5696 \
  altmannmarcelo/kmip:latest
# wait for initialization
docker exec kmip_${case_number} tail -F /var/log/pykmip/server.log | grep -i "Starting connection service"

# configure kmip with the base CA and server certificates
docker cp ${certs_dir}/ca.pem kmip_${case_number}:/opt/certs/root_certificate.pem
docker cp ${certs_dir}/server.key kmip_${case_number}:/opt/certs/server_key.pem
docker cp ${certs_dir}/server.crt kmip_${case_number}:/opt/certs/server_certificate.pem

# enforce permissions
docker exec -u root kmip_${case_number} chown -vR root:root /opt/certs/
docker exec -u root kmip_${case_number} chmod -vR 444 /opt/certs/

# restart kmip server
docker restart kmip_${case_number}
# check logs
docker exec kmip_${case_number} tail -100f /var/log/pykmip/server.log | grep -i "Starting connection service"

# edit mongod.conf
for i in $( seq 1 ${replica_count} ); do
  sudo bash -c "cat > ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf" << EOF
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
  enableEncryption: true
  kmip:
    serverName: ${server_ip}
    port: 5696
    clientCertificateFile: /mongodb/tls/mongodb.pem
    serverCAFile: /mongodb/tls/ca.pem
    # keyIdentifier: <key_name>

setParameter:
  authenticationMechanisms: SCRAM-SHA-256
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 528
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/*/mongod.conf

# restart psmdb
for i in $( seq ${replica_count} -1 1  ); do
  # stop container
  docker stop psmdb_${case_number}_${i}
  # remove data directory
  echo "removing data directory ${docker_base_dir}/psmdb_${case_number}_${i}/data"
  sudo rm -rf ${docker_base_dir}/psmdb_${case_number}_${i}/data
  # create data directory
  sudo mkdir -pv ${docker_base_dir}/psmdb_${case_number}_${i}/data
  # enforce permissions and ownership
  sudo chmod -v 755 ${docker_base_dir}/psmdb_${case_number}_${i}/data
  sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_${case_number}_${i}/data
  # start container
  docker start psmdb_${case_number}_${i}
done

# verify encryption success
for i in $( seq ${replica_count} -1 1  ); do
  echo -n "grep encryption success psmdb_${case_number}_${i}: ";sudo grep -i "Encryption keys DB is initialized successfully" ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log | tail -2
done

# done

# extra
## get certificates from the server
docker exec psmdb_${case_number}_${i} openssl s_client -showcerts -servername ${server_ip} -connect ${server_ip}:5696 -CAfile /mongodb/tls/ca.pem -cert /mongodb/tls/mongodb.pem

## container logs
docker logs kmip_${case_number} -f

# CURL test certs and CA
docker exec psmdb_${case_number}_${i} curl --cert /mongodb/tls/mongodb.pem --cacert /mongodb/tls/ca.pem -v https://${server_ip}:5696

# check kmip configuration
docker exec -u root kmip_${case_number} cat /opt/PyKMIP/server.conf
