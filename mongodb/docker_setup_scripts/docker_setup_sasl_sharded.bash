# configures SASL authentication for a sharded cluster. all the mongodb part is done on mongos

# create MongoDB containers
## ./docker_setup_psmdb_sharded.bash

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

## add PLAIN authentication to mongos config file
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

setParameter:
  authenticationMechanisms: SCRAM-SHA-256,PLAIN
EOF
cat ${docker_base_dir}/psmdb_${case_number}_mongos_1/mongos.conf
# check file - size should be around 328
ls -lart ${docker_base_dir}/psmdb_${case_number}_mongos_1/mongos.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_${case_number}_mongos_1/mongos.conf

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

# install cyrus packages for sasl
## if the packages cyrus-sasl cyrus-sasl-plain and cyrus-sasl-lib are not installed, install them
cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_mongos_1 rpm -qa | grep -i cyrus-sasl)
echo "cyrus_pkgs: ${cyrus_pkgs}"
if [[ -z "${cyrus_pkgs}" || $(echo ${cyrus_pkgs} | grep cyrus-sasl-plain | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep cyrus-sasl-lib | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep -E cyrus-sasl-[0-9] | wc -l) -eq 0 ]]; then
  docker exec -u root psmdb_${case_number}_mongos_1 microdnf install -y cyrus-sasl cyrus-sasl-plain cyrus-sasl-lib
fi
## if installation with microdnf fails, use curl to install the packages
cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_mongos_1 rpm -qa | grep -i cyrus-sasl)
if [[ -z "${cyrus_pkgs}" || $(echo ${cyrus_pkgs} | grep cyrus-sasl-plain | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep cyrus-sasl-lib | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep -E cyrus-sasl-[0-9] | wc -l) -eq 0 ]]; then
  docker exec -u root psmdb_${case_number}_mongos_1 curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cyrus-sasl-2.1.27-21.el9.x86_64.rpm
  docker exec -u root psmdb_${case_number}_mongos_1 curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cyrus-sasl-plain-2.1.27-21.el9.x86_64.rpm
  docker exec -u root psmdb_${case_number}_mongos_1 curl -O https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cyrus-sasl-lib-2.1.27-21.el9.x86_64.rpm
  docker exec -u root psmdb_${case_number}_mongos_1 rpm -iv cyrus-sasl-2.1.27-21.el9.x86_64.rpm cyrus-sasl-plain-2.1.27-21.el9.x86_64.rpm cyrus-sasl-lib-2.1.27-21.el9.x86_64.rpm
fi
## final check
cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_mongos_1 rpm -qa | grep -i cyrus-sasl)
echo "cyrus_pkgs: ${cyrus_pkgs}"

# config env file
docker exec psmdb_${case_number}_mongos_1 grep MECH /etc/sysconfig/saslauthd
docker exec -u root psmdb_${case_number}_mongos_1 sed -i -e s/^MECH=.*/MECH=ldap/g /etc/sysconfig/saslauthd
docker exec psmdb_${case_number}_mongos_1 grep MECH /etc/sysconfig/saslauthd

# copy config files to container
docker cp ${docker_base_dir}/saslauthd.conf psmdb_${case_number}_mongos_1:/etc/saslauthd.conf
docker cp ${docker_base_dir}/mongodb.conf psmdb_${case_number}_mongos_1:/etc/sasl2/mongodb.conf

# check files and permissions
docker exec psmdb_${case_number}_mongos_1 ls -lart /etc/sysconfig/saslauthd
docker exec psmdb_${case_number}_mongos_1 ls -lart /etc/saslauthd.conf
docker exec psmdb_${case_number}_mongos_1 ls -lart /etc/sasl2/mongodb.conf

# restart mongos container to apply SASL
docker restart psmdb_${case_number}_mongos_1
# start mongos process inside mongod container
docker exec psmdb_${case_number}_mongos_1 mongos -f /mongodb/mongos.conf
# start sasl # from /usr/lib/systemd/system/saslauthd.service
docker exec -u root psmdb_${case_number}_mongos_1 bash -c "/usr/sbin/saslauthd -m /var/run/saslauthd -a ldap > /tmp/saslauthd.log 2>&1"
# check if it is running
docker exec psmdb_${case_number}_mongos_1 ps aux
# change socket permission
docker exec -u root psmdb_${case_number}_mongos_1 chmod -v 755 /var/run/saslauthd
# test
docker exec psmdb_${case_number}_mongos_1 testsaslauthd -u john -p john_password  -f /var/run/saslauthd/mux
# 0: OK "Success."
docker exec psmdb_${case_number}_mongos_1 testsaslauthd -u john -p john_Xassword  -f /var/run/saslauthd/mux
# 0: NO "authentication failed"

# create SASL users
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('\$external').createUser({ user : 'john', roles: [{ role: 'readAnyDatabase', db: 'admin' }] })"
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('\$external').createUser({ user : 'mary', roles: [{ role: 'readWriteAnyDatabase', db: 'admin' }] })"
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationDatabase admin -u testuser -p testpwd --eval "db.getSiblingDB('\$external').createUser({ user : 'paul', roles: [{ role: 'readWrite', db: 'test' }] })"
# test connection with ldap user
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationMechanism PLAIN --authenticationDatabase \$external -u john -p john_password --eval "db.runCommand({ connectionStatus: 1 })"
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationMechanism PLAIN --authenticationDatabase \$external -u mary -p mary_password --eval "db.runCommand({ connectionStatus: 1 })"
docker exec psmdb_${case_number}_mongos_1 ${mongo_binary} --quiet --port 28017 --authenticationMechanism PLAIN --authenticationDatabase \$external -u paul -p paul_password --eval "db.runCommand({ connectionStatus: 1 })"

# done

# extra
## check container
docker ps | grep ${case_number}

## check ldap container logs
docker logs openldap_${case_number}

## check mongos log for authentication details
sudo grep john ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log

sudo grep conn12 ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log

sudo grep -i sasl ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log

sudo grep -i ldap ${docker_base_dir}/psmdb_${case_number}_mongos_1/log/mongos.log

## check saslauthd log
docker exec psmdb_${case_number}_mongos_1 cat /tmp/saslauthd.log

## kill mongos or saslauthd process
docker exec -u root psmdb_${case_number}_mongos_1 kill 60

## known errors
{"t":{"$date":"2025-12-29T13:58:15.439+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn16","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":2,"msg":"cannot connect to saslauthd server: No such file or directory"}}
{"t":{"$date":"2025-12-29T13:58:15.440+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn16","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":2,"msg":"Password verification failed"}}
### saslauthd is not running

{"t":{"$date":"2025-12-29T13:53:36.281+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn34","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":1,"msg":"SASL error opening password file. Have you performed the migration from db2 using cyrusbdb2current?\n"}}
{"t":{"$date":"2025-12-29T13:53:36.281+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn34","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":2,"msg":"Could not open /etc/sasl2/sasldb2"}}
{"t":{"$date":"2025-12-29T13:53:36.281+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn34","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":2,"msg":"Password verification failed"}}
### mongos not restarted after configuration changes
### no permission to read /etc/sasl2/mongodb.conf

{"t":{"$date":"2025-12-29T14:04:21.102+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn18","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":2,"msg":"Password verification failed"}}
### saslauthd might be using pam instead of ldap
### bind credentials are not correct in /etc/saslauthd.conf

{"t":{"$date":"2025-12-29T14:29:11.585+00:00"},"s":"I",  "c":"ACCESS",   "id":29052,   "svc":"R", "ctx":"conn14","msg":"SASL server message: ({priority}) {msg}","attr":{"priority":2,"msg":"Couldn't find mech PLAIN"}}
{"t":{"$date":"2025-12-29T14:29:11.585+00:00"},"s":"I",  "c":"ACCESS",   "id":5286307, "svc":"R", "ctx":"conn14","msg":"Failed to authenticate","attr":{"client":"127.0.0.1:55532","isSpeculative":false,"isClusterMember":false,"mechanism":"PLAIN","user":"","db":"$external","error":"OperationFailed: SASL step did not complete: (no mechanism available)","result":96,"metrics":{"conversation_duration":{"micros":330,"summary":{"0":{"step":1,"step_total":2,"duration_micros":194}}}},"doc":{"application":{"name":"mongosh 2.5.9"},"driver":{"name":"nodejs|mongosh","version":"6.19.0|2.5.9"},"platform":"Node.js v20.19.5, LE","os":{"name":"linux","architecture":"x64","version":"6.1.0-38-amd64","type":"Linux"},"env":{"container":{"runtime":"docker"}},"mongos":{"host":"679cc0101178:28017","client":"127.0.0.1:55532","version":"8.0.16-5"}},"extraInfo":{}}}"
### /etc/sasl2/mongodb.conf mech list is not correct. read permissions cause another error message
### changing mech list in saslauthd.conf causes no issues.
