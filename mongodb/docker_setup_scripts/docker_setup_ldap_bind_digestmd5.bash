# configures NativeLDAP authentication and authorization for a replica set. External bind via client's PLAIN credentials. TLS disabled
# https://hub.docker.com/r/bitnami/openldap
# https://gitlab.opencode.de/wzrdtales/bitnami-containers/-/tree/main/bitnami/openldap#configuration

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# reuse variables from previous scripts
server_ip="${net_prefix}.99"
sasl_realm="PERCONA.REALM"

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

# install SASL packages on ldap server for DIGEST-MD5 support
docker exec -u root openldap_${case_number} apt-get update
docker exec -u root openldap_${case_number} apt-get install -y libsasl2-modules sasl2-bin libsasl2-modules-db

# create SASL configuration file for slapd
cat > ${docker_base_dir}/slapd_sasl.conf << 'EOF'
pwcheck_method: auxprop
auxprop_plugin: sasldb
sasldb_path: /etc/sasldb2
mech_list: DIGEST-MD5 EXTERNAL
EOF
docker cp ${docker_base_dir}/slapd_sasl.conf openldap_${case_number}:/usr/lib/x86_64-linux-gnu/sasl2/slapd.conf

# Set permissions on SASL database and config files so slapd (user 1001) can read them
docker exec -u root openldap_${case_number} chown -v 1001:root /etc/sasldb2
docker exec -u root openldap_${case_number} chmod -v 640 /etc/sasldb2
docker exec -u root openldap_${case_number} chown -v 1001:root /usr/lib/x86_64-linux-gnu/sasl2/slapd.conf

# check SASL database
docker exec openldap_${case_number} ls -la /etc/sasldb2
docker exec openldap_${case_number} ls -la /usr/lib/x86_64-linux-gnu/sasl2/slapd.conf
docker exec openldap_${case_number} cat /usr/lib/x86_64-linux-gnu/sasl2/slapd.conf

# create OpenLDAP config file to allow DIGEST-MD5 authentication
cat > ${docker_base_dir}/sasl_olc_config.ldif << EOF
dn: cn=config
changetype: modify
replace: olcSaslSecProps
olcSaslSecProps: noanonymous,minssf=0
-
replace: olcSaslAuxprops
olcSaslAuxprops: sasldb
-
replace: olcSaslRealm
olcSaslRealm: ${sasl_realm}
EOF
docker cp ${docker_base_dir}/sasl_olc_config.ldif openldap_${case_number}:/tmp/sasl_olc_config.ldif

# apply SASL OpenLDAP config
docker exec openldap_${case_number} ldapmodify -v -Y EXTERNAL -H ldapi:/// -f /tmp/sasl_olc_config.ldif

# verify SASL config was applied
docker exec openldap_${case_number} ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config "(objectClass=olcGlobal)" olcSaslSecProps olcSaslAuxprops olcSaslRealm

# restart to apply all SASL changes
docker restart openldap_${case_number}

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

# create users in SASL database (required for DIGEST-MD5)
docker exec openldap_${case_number} bash -c "echo 'secret' | saslpasswd2 -c -p -u '${sasl_realm}' 'cn=ldapadm,dc=percona,dc=local'"
for name in ${names}
do
  docker exec openldap_${case_number} bash -c "echo '${name}_password' | saslpasswd2 -c -p -u '${sasl_realm}' 'cn=${name},ou=users,dc=percona,dc=local'"
done
# verify SASL users were created - should list the 4 above with PERCONA.REALM
docker exec openldap_${case_number} sasldblistusers2

# test DIGEST-MD5 authentication to LDAP server
docker exec openldap_${case_number} ldapsearch -LLL -Y DIGEST-MD5 -U "cn=ldapadm,dc=percona,dc=local" -R "${sasl_realm}" -w secret -b "dc=percona,dc=local" "objectclass=person" dn
for name in ${names}
do
  docker exec openldap_${case_number} ldapsearch -LLL -Y DIGEST-MD5 -U "cn=${name},ou=users,dc=percona,dc=local" -R "${sasl_realm}" -w ${name}_password -b "dc=percona,dc=local" "objectclass=person" dn
done

# config file with LDAP
# database receives the SASL realm from the LDAP server during DIGEST-MD5 handshake
# the queryTemplate uses LDAP DN structure for authorization lookups
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
      method: sasl
      saslMechanisms: DIGEST-MD5
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
# check files - size should be around 782
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/*/mongod.conf

# install packages and restart mongod containers to apply new config
for i in $( seq ${replica_count} -1 1  ); do
  ## if the package cyrus-sasl-md5 is not installed, install it
  cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_${i} rpm -qa | grep -i cyrus-sasl)
  echo "cyrus_pkgs: ${cyrus_pkgs}"
  if [[ -z "${cyrus_pkgs}" || $(echo ${cyrus_pkgs} | grep cyrus-sasl-md5 | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep cyrus-sasl-lib | wc -l) -eq 0 ]]; then
    docker exec -u root psmdb_${case_number}_${i} microdnf install -y cyrus-sasl-md5 cyrus-sasl-lib
  fi
  ## if installation with microdnf fails, use curl to install the packages
  cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_${i} rpm -qa | grep -i cyrus-sasl)
  if [[ -z "${cyrus_pkgs}" || $(echo ${cyrus_pkgs} | grep cyrus-sasl-md5 | wc -l) -eq 0 || $(echo ${cyrus_pkgs} | grep cyrus-sasl-lib | wc -l) -eq 0 ]]; then
    docker exec -u root psmdb_${case_number}_${i} curl -O https://www.rpmfind.net/linux/almalinux/9.7/AppStream/x86_64/os/Packages/cyrus-sasl-md5-2.1.27-22.el9.x86_64.rpm
    docker exec -u root psmdb_${case_number}_${i} curl -O https://www.rpmfind.net/linux/almalinux/9.7/BaseOS/x86_64/os/Packages/cyrus-sasl-lib-2.1.27-22.el9.x86_64.rpm
    docker exec -u root psmdb_${case_number}_${i} rpm -ivh cyrus-sasl-lib-2.1.27-22.el9.x86_64.rpm
    docker exec -u root psmdb_${case_number}_${i} rpm -ivh cyrus-sasl-md5-2.1.27-22.el9.x86_64.rpm
  fi
  ## final check
  cyrus_pkgs=$(docker exec -u root psmdb_${case_number}_${i} rpm -qa | grep -i cyrus-sasl)
  echo "cyrus_pkgs: ${cyrus_pkgs}"

  docker restart psmdb_${case_number}_${i}
done

# done

# extra
## refer to docker_setup_ldap.bash for authentication and authorization tests

# debug
sudo tail -200f ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log

sudo grep -i john ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log | tail -100

sudo grep conn38 ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log | tail -100

sudo grep -i authentication ${docker_base_dir}/psmdb_${case_number}_1/log/mongod.log | tail -50

docker logs openldap_${case_number} > openldap.log 2>&1
tail -100 openldap.log

# Test LDAP connection from MongoDB container
docker exec -u root psmdb_${case_number}_${i} microdnf install -y openldap-clients
ldapsearch -x -H ldap://${ldap_ip}:389 -D "cn=ldapadm,dc=percona,dc=local" -w secret -b "dc=percona,dc=local" "objectclass=person" dn

## STRACE DEBUG
# use strace to find out file dependencies
docker exec -u root openldap_${case_number} apt-get install strace -y

# Run a new command
docker exec -u root openldap_${case_number} strace -f -e openat ldapsearch -LLL -Y DIGEST-MD5 -U mary -R "${sasl_realm}" -w mary_password -b "dc=percona,dc=local" "objectclass=person" dn

# Attach strace to running process (e.g., PID 1)
docker exec -u root openldap_${case_number} pgrep slapd
docker exec -u root openldap_${case_number} strace -f -p 1 -e openat


# delete users IF NEEDED
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=person" dn | awk -F": " '$1~/^\s*dn/{print $2}' | ldapdelete -D "cn=ldapadm,dc=percona,dc=local" -w secret -r

# delete groups IF NEEDED
docker exec openldap_${case_number} ldapsearch -LLL -b "dc=percona,dc=local" -D "cn=ldapadm,dc=percona,dc=local" -w secret "objectclass=groupOfNames" dn | awk -F": " '\$1~/^\s*dn/{print \$2}' | ldapdelete -D "cn=ldapadm,dc=percona,dc=local" -w secret -r
