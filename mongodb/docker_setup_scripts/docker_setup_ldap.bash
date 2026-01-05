# configures NativeLDAP authentication and authorization for a replica set. Simple bind, TLS disabled
# https://hub.docker.com/r/bitnami/openldap
# https://gitlab.opencode.de/wzrdtales/bitnami-containers/-/tree/main/bitnami/openldap#configuration

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# reuse variables from previous scripts
server_ip="${net_prefix}.99"

# cleanup
docker rm -f openldap_${case_number}
docker network rm ${net_name}

# deploy ldap container
docker run --detach --network ${net_name} --ip ${server_ip} --name openldap_${case_number} \
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

# create groups file
rm -fv ${docker_base_dir}/groups.ldif
cat > ${docker_base_dir}/groups.ldif <<EOF
dn: cn=dba,ou=groups,dc=percona,dc=local
objectClass: groupOfNames
cn: dba
member: cn=john,ou=users,dc=percona,dc=local
member: cn=mary,ou=users,dc=percona,dc=local

dn: cn=support,ou=groups,dc=percona,dc=local
objectClass: groupOfNames
cn: support
member: cn=mary,ou=users,dc=percona,dc=local
member: cn=paul,ou=users,dc=percona,dc=local

dn: cn=finance,ou=groups,dc=percona,dc=local
objectClass: groupOfNames
cn: finance
member: cn=john,ou=users,dc=percona,dc=local
member: cn=paul,ou=users,dc=percona,dc=local
EOF
cat ${docker_base_dir}/groups.ldif
# copy to container
docker cp ${docker_base_dir}/groups.ldif openldap_${case_number}:/tmp/groups.ldif

# create LDAP users
docker exec openldap_${case_number} ldapadd -D "cn=ldapadm,dc=percona,dc=local" -w secret -f /tmp/users.ldif
# create LDAP groups
docker exec openldap_${case_number} ldapadd -D "cn=ldapadm,dc=percona,dc=local" -w secret -f /tmp/groups.ldif
# check LDAP users
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=person" dn
# check LDAP groups
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=groupOfNames" dn

# config file with LDAP
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
  authorization: enabled
  ldap:
    servers: ${server_ip}
    validateLDAPServerConfig: false
    transportSecurity: none
    bind:
      method: simple
      queryUser: "cn=ldapadm,dc=percona,dc=local"
      queryPassword: secret
    authz:
      queryTemplate: "ou=groups,dc=percona,dc=local??sub?(&(objectClass=groupOfNames)(member={USER}))"
    userToDNMapping: >-
      [
        {
          match : "(.+)",
          substitution: "cn={0},ou=users,dc=percona,dc=local"
        }
      ]

setParameter:
  authenticationMechanisms: SCRAM-SHA-256,PLAIN
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 829
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/*/mongod.conf

# restart to apply LDAP
for i in $( seq ${replica_count} -1 1  ); do
  docker restart psmdb_${case_number}_${i}
done

# done

# extra
## test connection with SCRAM user
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.runCommand( { connectionStatus: 1 } )'

## create MongoDB LDAP roles
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createRole( { role: "cn=dba,ou=groups,dc=percona,dc=local", privileges: [], roles: [{role: "readWrite", db: "reports"}] })'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createRole( { role: "cn=support,ou=groups,dc=percona,dc=local", privileges: [], roles:[{role: "read", db: "reports"}] })'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("admin").createRole({ role: "cn=finance,ou=groups,dc=percona,dc=local", privileges: [], roles: [{role: "read", db: "invoices"}] })'

## test connection with ldap users
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationMechanism PLAIN --authenticationDatabase \$external -u mary -p mary_password --eval 'db.runCommand( { connectionStatus: 1 } )'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationMechanism PLAIN --authenticationDatabase \$external -u john -p john_password --eval 'db.runCommand( { connectionStatus: 1 } )'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationMechanism PLAIN --authenticationDatabase \$external -u paul -p paul_password --eval 'db.runCommand( { connectionStatus: 1 } )'

## authorization tests
### create dummy data
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("reports").getCollection("monthly").insertMany([{"name": "Invoices Received", "type": "pdf"}, {"name": "Invoices Sent", "type": "pdf"}, {"name": "Employees Hired", "type": "xls"}])'
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet --authenticationDatabase admin -u testuser -p testpwd --eval 'db.getSiblingDB("invoices").getCollection("january").insertMany([{"name": "Printer", "value": 500.00}, {"name": "Tonner", "value": 150.00}])'

### test access
### JOHN - dba + finance (write reports, read invoices)
#### READ from reports database (should FAIL - write role doesn't include read)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u john -p john_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('reports').getCollection('monthly').find().toArray()"
#### WRITE to reports database (should SUCCEED - has write on reports)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u john -p john_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('reports').getCollection('monthly').insertOne({name: 'Test Report by John', type: 'doc'})"
#### READ from invoices database (should SUCCEED - has read on invoices)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u john -p john_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('invoices').getCollection('january').find().toArray()"
#### WRITE to invoices database (should FAIL - only has read on invoices)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u john -p john_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('invoices').getCollection('january').insertOne({name: 'New Invoice by John', value: 999.99})"

### MARY - dba + support (write reports, read reports)
#### READ from reports database (should SUCCEED - has read on reports via support)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u mary -p mary_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('reports').getCollection('monthly').find().toArray()"
#### WRITE to reports database (should SUCCEED - has write on reports via dba)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u mary -p mary_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('reports').getCollection('monthly').insertOne({name: 'Test Report by Mary', type: 'csv'})"
#### READ from invoices database (should FAIL - no permissions on invoices)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u mary -p mary_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('invoices').getCollection('january').find().toArray()"
#### WRITE to invoices database (should FAIL - no permissions on invoices)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u mary -p mary_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('invoices').getCollection('january').insertOne({name: 'New Invoice by Mary', value: 250.00})"

### PAUL - support + finance (read reports, read invoices)
#### READ from reports database (should SUCCEED - has read on reports)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u paul -p paul_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('reports').getCollection('monthly').find().toArray()"
#### WRITE to reports database (should FAIL - only has read permission)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u paul -p paul_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('reports').getCollection('monthly').insertOne({name: 'Test Report by Paul', type: 'txt'})"
#### READ from invoices database (should SUCCEED - has read on invoices)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u paul -p paul_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('invoices').getCollection('january').find().toArray()"
# WRITE to invoices database (should FAIL - only has read permission)
docker exec psmdb_${case_number}_1 ${mongo_binary} --quiet -u paul -p paul_password --authenticationMechanism PLAIN --authenticationDatabase \$external --eval "db.getSiblingDB('invoices').getCollection('january').insertOne({name: 'New Invoice by Paul', value: 100.00})"

# cleanup
## delete LDAP users
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=person" dn | awk -F": " '$1~/^\s*dn/{print $2}' | ldapdelete -D "cn=ldapadm,dc=percona,dc=local" -w secret -r
## delete LDAP groups
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=groupOfNames" dn | awk -F": " '\$1~/^\s*dn/{print \$2}' | ldapdelete -D "cn=ldapadm,dc=percona,dc=local" -w secret -r

# check container
docker ps | grep ${case_number}

# check ldap container logs
docker logs openldap_${case_number}

# check mongod log for authentication details
sudo grep john ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep conn12 ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep -i sasl ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep -i ldap ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log
