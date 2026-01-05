# configures SASL authentication for a replica set

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# reuse variables from previous scripts
server_ip="${net_prefix}.99"

# cleanup
docker rm -f openldap_${case_number}
docker network rm ${net_name}

# deploy ldap container
docker run --detach  --network ${net_name} --ip ${server_ip} --name openldap_${case_number} \
  --env LDAP_ADMIN_USERNAME=ldapadm \
  --env LDAP_ADMIN_PASSWORD=secret \
  --env LDAP_ROOT=dc=percona,dc=local \
  --env LDAP_ADMIN_DN=cn=ldapadm,dc=percona,dc=local \
  --env LDAP_PORT_NUMBER=389 \
  --env LDAP_LDAPS_PORT_NUMBER=636 \
  --env LDAP_LOGLEVEL=-1 \
  bitnami/openldap:latest
# check logs and wait for INFO  ==> ** Starting slapd **
docker logs -f openldap_${case_number} 2>&1 | grep "Starting slapd"

# create users file
rm -fv ${docker_base_dir}/users.ldif
names="john
mary
paul"
for name in ${names}
do
  cat >> ${docker_base_dir}/users.ldif <<EOF
dn: cn=${name},ou=users,dc=percona,dc=local
objectClass: person
sn:${name}
cn:${name}
userPassword:${name}_password

EOF
done
cat ${docker_base_dir}/users.ldif
# copy to container
docker cp ${docker_base_dir}/users.ldif openldap_${case_number}:/tmp/users.ldif

# create LDAP users
docker exec openldap_${case_number} ldapadd -D "cn=ldapadm,dc=percona,dc=local" -w secret -f /tmp/users.ldif
# check LDAP users
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=person" dn

##### MONGODB PART #####

## add PLAIN authentication to mongod config file
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

setParameter:
  authenticationMechanisms: SCRAM-SHA-256,PLAIN
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 338
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf

# config sasl service file
cat > ${docker_base_dir}/saslauthd.conf << EOF
ldap_servers: ldap://${server_ip}
ldap_mech: PLAIN
ldap_search_base: dc=percona,dc=local
ldap_filter: (cn=%u)
ldap_bind_dn: cn=ldapadm,dc=percona,dc=local
ldap_password: secret
EOF
cat ${docker_base_dir}/saslauthd.conf

# configure mongodb sasl config file
cat > ${docker_base_dir}/mongodb.conf << EOF
pwcheck_method: saslauthd
saslauthd_path: /var/run/saslauthd/mux
log_level: 5
mech_list: PLAIN
EOF
cat ${docker_base_dir}/mongodb.conf

# install and setup SASL
for i in $( seq 1 ${replica_count} ); do
  ## if the packages cyrus-sasl cyrus-sasl-plain and cyrus-sasl-lib are not installed, install them
  cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_${i} rpm -qa | grep -i cyrus-sasl)
  echo "cyrus_pkgs: ${cyrus_pkgs}"
  if [[ -z "${cyrus_pkgs}" || $(echo ${cyrus_pkgs} | grep cyrus-sasl-plain | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep cyrus-sasl-lib | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep -E cyrus-sasl-[0-9] | wc -l) -eq 0 ]]; then
    docker exec -u root psmdb_${case_number}_${i} microdnf install -y cyrus-sasl cyrus-sasl-plain cyrus-sasl-lib
  fi
  ## if installation with microdnf fails, use curl to install the packages
  cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_${i} rpm -qa | grep -i cyrus-sasl)
  if [[ -z "${cyrus_pkgs}" || $(echo ${cyrus_pkgs} | grep cyrus-sasl-plain | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep cyrus-sasl-lib | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep -E cyrus-sasl-[0-9] | wc -l) -eq 0 ]]; then
    docker exec -u root psmdb_${case_number}_${i} curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cyrus-sasl-2.1.27-21.el9.x86_64.rpm
    docker exec -u root psmdb_${case_number}_${i} curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cyrus-sasl-plain-2.1.27-21.el9.x86_64.rpm
    docker exec -u root psmdb_${case_number}_${i} curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cyrus-sasl-lib-2.1.27-21.el9.x86_64.rpm
    docker exec -u root psmdb_${case_number}_${i} rpm -iv cyrus-sasl-2.1.27-21.el9.x86_64.rpm cyrus-sasl-plain-2.1.27-21.el9.x86_64.rpm cyrus-sasl-lib-2.1.27-21.el9.x86_64.rpm
  fi
  ## final check
  cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_${i} rpm -qa | grep -i cyrus-sasl)
  echo "cyrus_pkgs: ${cyrus_pkgs}"

  # config env file
  docker exec psmdb_${case_number}_${i} grep MECH /etc/sysconfig/saslauthd
  docker exec -u root psmdb_${case_number}_${i} sed -i -e s/^MECH=.*/MECH=ldap/g /etc/sysconfig/saslauthd
  docker exec psmdb_${case_number}_${i} grep MECH /etc/sysconfig/saslauthd

  # copy config files to container
  docker cp ${docker_base_dir}/saslauthd.conf psmdb_${case_number}_${i}:/etc/saslauthd.conf
  docker cp ${docker_base_dir}/mongodb.conf psmdb_${case_number}_${i}:/etc/sasl2/mongodb.conf

  # check files and permissions
  docker exec psmdb_${case_number}_${i} ls -lart /etc/sysconfig/saslauthd
  docker exec psmdb_${case_number}_${i} ls -lart /etc/saslauthd.conf
  docker exec psmdb_${case_number}_${i} ls -lart /etc/sasl2/mongodb.conf
done

# restart to apply SASL
for i in $( seq ${replica_count} -1 1  ); do
  # restart mongod container
  docker restart psmdb_${case_number}_${i}
  # start sasl # from /usr/lib/systemd/system/saslauthd.service
  docker exec -u root psmdb_${case_number}_${i} bash -c "/usr/sbin/saslauthd -m /var/run/saslauthd -a ldap > /tmp/saslauthd.log 2>&1"
  # check if it is running
  docker exec psmdb_${case_number}_${i} ps aux
  # change socket permission
  docker exec -u root psmdb_${case_number}_${i} chmod -v 755 /var/run/saslauthd
  # test
  docker exec psmdb_${case_number}_${i} testsaslauthd -u john -p john_password  -f /var/run/saslauthd/mux
  # 0: OK "Success."
  docker exec psmdb_${case_number}_${i} testsaslauthd -u john -p john_Xassword  -f /var/run/saslauthd/mux
  # 0: NO "authentication failed"
done

# create SASL users
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('\$external').createUser({ user : 'john', roles: [{ role: 'readAnyDatabase', db: 'admin' }] })"
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('\$external').createUser({ user : 'mary', roles: [{ role: 'readWriteAnyDatabase', db: 'admin' }] })"
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('\$external').createUser({ user : 'paul', roles: [{ role: 'readWrite', db: 'test' }] })"
# test connection with ldap user
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationMechanism PLAIN --authenticationDatabase \$external -u john -p john_password --eval "db.runCommand({ connectionStatus: 1 })"
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationMechanism PLAIN --authenticationDatabase \$external -u mary -p mary_password --eval "db.runCommand({ connectionStatus: 1 })"
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationMechanism PLAIN --authenticationDatabase \$external -u paul -p paul_password --eval "db.runCommand({ connectionStatus: 1 })"

# done

# extra
## check container
docker ps | grep ${case_number}

## check ldap container logs
docker logs openldap_${case_number}

## check mongod log for authentication details
sudo grep john ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep conn12 ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep -i sasl ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep -i ldap ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

## check saslauthd log
docker exec psmdb_${case_number}_1 cat /tmp/saslauthd.log
