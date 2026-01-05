# configures NativeLDAP authentication and authorization for a replica set. Simple bind, TLS enabled between MongoDB and LDAP, not for clients
# https://hub.docker.com/r/bitnami/openldap
# https://gitlab.opencode.de/wzrdtales/bitnami-containers/-/tree/main/bitnami/openldap#configuration

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# create Base CA and certificates
## ./docker_setup_tls_base_certs.sh

# reuse variables from previous scripts

# cleanup
docker rm -f openldap_${case_number}
docker network rm ${net_name}

# deploy ldap container
docker run --detach --network ${net_name} --ip ${server_ip} --name openldap_${case_number} \
  -v ${certs_dir}:/opt/bitnami/openldap/certs \
  --env LDAP_ADMIN_USERNAME=ldapadm \
  --env LDAP_ADMIN_PASSWORD=secret \
  --env LDAP_ROOT=dc=percona,dc=local \
  --env LDAP_ADMIN_DN=cn=ldapadm,dc=percona,dc=local \
  --env LDAP_PORT_NUMBER=389 \
  --env LDAP_LDAPS_PORT_NUMBER=636 \
  --env LDAP_ENABLE_TLS=yes \
  --env LDAP_TLS_CERT_FILE=/opt/bitnami/openldap/certs/server.crt \
  --env LDAP_TLS_KEY_FILE=/opt/bitnami/openldap/certs/server.key \
  --env LDAP_TLS_CA_FILE=/opt/bitnami/openldap/certs/ca.crt \
  --env LDAP_LOGLEVEL=-1 \
  bitnami/openldap:latest
# check logs and wait for INFO  ==> ** Starting slapd **
docker logs -f openldap_${case_number} 2>&1 | grep -i "Starting slapd\|olcTLSCACertificateFile:\|olcTLSCertificateFile:\|olcTLSCertificateKeyFile:"

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

# check TLS config
docker exec openldap_${case_number} ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config olcTLSCACertificateFile olcTLSCertificateFile olcTLSCertificateKeyFile

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
    transportSecurity: tls
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
# check files - size should be around 834
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/*/mongod.conf

# create the ldap.conf file with LDAP server CA
cat > ${docker_base_dir}/ldap.conf <<EOF
TLS_CACERT /mongodb/tls/ca.crt
TLS_REQCERT demand
EOF
cat ${docker_base_dir}/ldap.conf
for i in $( seq ${replica_count} -1 1  ); do
  # copy ldap file to the container
  docker cp ${docker_base_dir}/ldap.conf psmdb_${case_number}_${i}:/etc/openldap/ldap.conf
  # restart mongod container from the main terminal
  docker restart psmdb_${case_number}_${i}
done

# done

# extra
## check extra session in ./docker_setup_ldap.bash for authentication and authorization tests

## TLS command to fetch server certificates
docker exec psmdb_${case_number}_1 bash -c "openssl s_client -showcerts -servername ${server_ip} -connect ${server_ip}:636 -CAfile /mongodb/tls/ca.crt"
