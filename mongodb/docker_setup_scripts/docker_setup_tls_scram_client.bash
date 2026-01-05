# x509 certificates are used for internal authentication, clients use SCRAM-SHA-256

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# create Base CA and certificates
# ./docker_setup_tls_base_certs.sh

# reuse variables from previous scripts

# create client users
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/localhost --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('admin').createUser({ user : 'john', pwd: 'john_password', roles: [{ role: 'readAnyDatabase', db: 'admin' }]})"
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/localhost --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('admin').createUser({ user : 'mary', pwd: 'mary_password', roles: [{ role: 'readWriteAnyDatabase', db: 'admin' }]})"
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/localhost --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('admin').createUser({ user : 'paul', pwd: 'paul_password', roles: [{ role: 'readWrite', db: 'test' }]})"
# check client users
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host localhost --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('admin').getUsers()"

# config file with TLS
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
    tls:
      mode: requireTLS
      certificateKeyFile: /mongodb/tls/mongodb.pem
      CAFile: /mongodb/tls/ca.crt

  storage:
    dbPath: /mongodb/data
    directoryPerDB: true

  replication:
    replSetName: rs-${case_number}

  security:
    clusterAuthMode: x509

  setParameter:
    authenticationMechanisms: SCRAM-SHA-256
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 478
ls -lart ${docker_base_dir}/psmdb_${case_number}_*/mongod.conf

# restart containers to apply the TLS configs in mongod.conf
for i in $( seq ${replica_count} -1 1  ); do
  docker restart psmdb_${case_number}_${i}
done

# done

# extra
# test connection with SCRAM user + TLS
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin -u testuser -p testpwd --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/john.pem --eval 'db.runCommand( { connectionStatus: 1} )'
# test connection with x509 users
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin -u john -p john_password --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/john.pem --eval 'db.runCommand( { connectionStatus: 1} )'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin -u mary -p mary_password --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/mary.pem --eval 'db.runCommand( { connectionStatus: 1} )'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin -u paul -p paul_password --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/paul.pem --eval 'db.runCommand( { connectionStatus: 1} )'

# create dummy data
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/localhost --authenticationDatabase admin --u testuser -p testpwd --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/paul.pem --eval 'db.getSiblingDB("reports").getCollection("monthly").insertMany([{"name": "Invoices Received", "type": "pdf"}, {"name": "Invoices Sent", "type": "pdf"}, {"name": "Employees Hired", "type": "xls"}])'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/localhost --authenticationDatabase admin --u testuser -p testpwd --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/paul.pem --eval 'db.getSiblingDB("invoices").getCollection("january").insertMany([{"name": "Printer", "value": 500.00}, {"name": "Tonner", "value": 150.00}])'

# authorization tests
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/john.pem --eval "db.getSiblingDB('reports').getCollection('monthly').findOne()"
## should work
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/john.pem --eval 'db.getSiblingDB("reports").getCollection("monthly").insertMany([{"name": "Invoices Received", "type": "pdf"}, {"name": "Invoices Sent", "type": "pdf"}, {"name": "Employees Hired", "type": "xls"}])'
## should fail
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/mary.pem --eval 'db.getSiblingDB("reports").getCollection("monthly").insertMany([{"name": "Invoices Received", "type": "pdf"}, {"name": "Invoices Sent", "type": "pdf"}, {"name": "Employees Hired", "type": "xls"}])'
## should work
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/paul.pem --eval "db.getSiblingDB('reports').getCollection('monthly').findOne()"
## should fail
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --host rs-${case_number}/${psmdb_ip_1} --authenticationDatabase admin --tls --tlsCAFile /mongodb/tls/ca.crt --tlsCertificateKeyFile /mongodb/tls/paul.pem --eval 'db.getSiblingDB("test").getCollection("monthly").insertMany([{"name": "Invoices Received", "type": "pdf"}, {"name": "Invoices Sent", "type": "pdf"}, {"name": "Employees Hired", "type": "xls"}])'
## should work
