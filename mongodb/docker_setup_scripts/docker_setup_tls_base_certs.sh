# creates the CA and the signed certificates for mongodb and clients

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# reuses variables from previous scripts
certs_dir=/bigdisk/${case_number}/tls_base_certs
server_ip="${net_prefix}.99"

# cleanup
sudo rm -rfv ${certs_dir}
for i in $( seq 1 ${replica_count} ); do
  sudo rm -rfv ${docker_base_dir}/psmdb_${case_number}_${i}/tls/
done

# initialize folders
mkdir -pv ${certs_dir}
for i in $( seq 1 ${replica_count} ); do
  sudo mkdir -pv ${docker_base_dir}/psmdb_${case_number}_${i}/tls/
done

# CA key and crt
openssl req -nodes -x509 -newkey rsa:4096 -keyout ${certs_dir}/ca.key -out ${certs_dir}/ca.crt -subj "/C=US/ST=California/L=SanFrancisco/O=Percona/OU=root/CN=localhost"
# CA PEM
cat ${certs_dir}/ca.key ${certs_dir}/ca.crt > ${certs_dir}/ca.pem
# create server CSR (LDAP, Vault, KMIP...)
openssl req -nodes -newkey rsa:4096 -keyout ${certs_dir}/server.key -out ${certs_dir}/server.csr -subj "/C=US/ST=California/L=SanFrancisco/O=Percona/OU=HR/CN=localhost" -addext "extendedKeyUsage=serverAuth" -addext "keyUsage=digitalSignature"
# create mongodb CSR
openssl req -nodes -newkey rsa:4096 -keyout ${certs_dir}/mongodb.key -out ${certs_dir}/mongodb.csr -subj "/C=PT/ST=Porto/L=Gaia/O=PerconaPT/OU=Support/CN=localhost" -addext "extendedKeyUsage=serverAuth,clientAuth" -addext "keyUsage=digitalSignature"

# client certificates
names="john
mary
paul"
for name in ${names}
do
  ## generate client CSR
  sudo openssl req -nodes -newkey rsa:4096 -keyout ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.key -out ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.csr -subj "/CN=${name}/OU=users/DC=percona/DC=local"
  ## sign with server CA
  sudo openssl x509 -req -in ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.csr -CA ${certs_dir}/ca.crt -CAkey ${certs_dir}/ca.key -set_serial 02 -out ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.crt -days 365
  ## create Client PEM
  sudo cat ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.key ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.crt | sudo tee ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.pem >/dev/null
  ## verify with CA
  echo -n "check CA: ";sudo openssl verify -verbose -CAfile ${certs_dir}/ca.crt ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.pem
  ## create user variable
  declare ${name}_user=$(sudo openssl x509 -in ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.pem -inform PEM -subject -nameopt RFC2253 | grep -i subject | awk -F 'subject=' '{print $2}')
  varname=${name}_user
  echo "${varname}: "${!varname}
  ## expected output: subject=DC=local,DC=percona,OU=users,CN={name}
  ## copy client certs to other containers
  for i in $( seq 2 ${replica_count} ); do
    sudo cp -v ${docker_base_dir}/psmdb_${case_number}_1/tls/${name}.* ${docker_base_dir}/psmdb_${case_number}_${i}/tls/
  done
  echo "-----------"
done

# create mongodb certificates
for i in $( seq 1 ${replica_count} ); do
  declare psmdb_ip_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psmdb_${case_number}_${i})
  varname=psmdb_ip_${i}
  echo "${varname}: "${!varname}
  ## create extfile
  printf "subjectAltName=IP:${!varname}\nextendedKeyUsage = serverAuth,clientAuth" | sudo tee ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.extfile
  echo ""
  ## sign
  sudo openssl x509 -req -in ${certs_dir}/mongodb.csr -CA ${certs_dir}/ca.crt -CAkey ${certs_dir}/ca.key -set_serial 01 -out ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.crt -extfile ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.extfile -days 365
  ## remove extfile
  sudo rm -fv ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.extfile
  ## create PEMs
  sudo cat ${certs_dir}/mongodb.key ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.crt | sudo tee ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.pem >/dev/null
  ## verify SAN
  echo -n "check SAN: ";sudo openssl x509 -in ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.pem -text -noout | grep 'IP Address'
  ## verify with CA
  echo -n "check CA: ";sudo openssl verify -verbose -CAfile ${certs_dir}/ca.crt ${docker_base_dir}/psmdb_${case_number}_${i}/tls/mongodb.pem
  ## copy CA to container mount
  sudo cp -v ${certs_dir}/ca.{pem,crt} ${docker_base_dir}/psmdb_${case_number}_${i}/tls/
  ## fix permissions
  sudo chown -vR 1001:1001 ${docker_base_dir}/psmdb_${case_number}_${i}/tls/
  echo "-----------"
done

# create server (LDAP, KMIP, Vault...) certificates
## create extfile
printf "subjectAltName=IP:${server_ip}\nextendedKeyUsage = serverAuth" | sudo tee ${certs_dir}/server.extfile
## sign
sudo openssl x509 -req -in ${certs_dir}/server.csr -CA ${certs_dir}/ca.crt -CAkey ${certs_dir}/ca.key -set_serial 01 -out ${certs_dir}/server.crt -extfile ${certs_dir}/server.extfile -days 365
## remove extfile
sudo rm -fv ${certs_dir}/server.extfile
## create PEM
sudo cat ${certs_dir}/server.key ${certs_dir}/server.crt | sudo tee ${certs_dir}/server.pem >/dev/null
## verify SAN
echo -n "check SAN: ";sudo openssl x509 -in ${certs_dir}/server.pem -text -noout | grep 'IP Address'
## verify with CA
echo -n "check CA: ";sudo openssl verify -verbose -CAfile ${certs_dir}/ca.crt ${certs_dir}/server.pem

# set permissions
sudo chown -vR 1001:1001 ${certs_dir}
sudo chmod -v 444 ${certs_dir}/*

# done

# extra
## check files
ls -lart ${certs_dir}/*
ls -lart ${docker_base_dir}/psmdb_${case_number}_${i}/tls/*
