# configures OpenBao server for data-at-rest encryption for a replica set. TLS enabled between MongoDB and OpenBao.
# https://docs.percona.com/percona-server-for-mongodb/8.0/openbao.html

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# create Base CA and certificates
## ./docker_setup_tls_base_certs.sh

# reuse variables from previous scripts
openbao_dir="${docker_base_dir}/openbao"

# cleanup
docker rm -f openbao_${case_number}
docker network rm ${net_name}
sudo rm -rf ${openbao_dir}

# initialize folders
mkdir -pv ${openbao_dir}/{config,storage,tls}

# copy server certificates to openbao directory
cp -v ${certs_dir}/server.key ${openbao_dir}/tls/server.key
cp -v ${certs_dir}/server.crt ${openbao_dir}/tls/server.crt
cp -v ${certs_dir}/ca.crt ${openbao_dir}/tls/ca.crt
# enforce permissions
sudo chmod -vR 400 ${openbao_dir}/tls/*

# create openbao config file
cat > ${openbao_dir}/config/openbao.hcl << EOF
listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/openbao/tls/server.crt"
  tls_key_file = "/openbao/tls/server.key"
}

storage "file" {
  path = "/openbao/storage"
}

disable_mlock = true
log_level = "Debug"
api_addr = "https://${server_ip}:8200"
EOF
cat ${openbao_dir}/config/openbao.hcl

# create PSMDB access policy
cat > ${openbao_dir}/config/psmdb-access.hcl << EOF
path "secret/data/*" {
  capabilities = ["create","read","update","delete"]
}
path "secret/metadata/*" {
  capabilities = ["read"]
}
path "secret/config" {
  capabilities = ["read"]
}
EOF
# check policy
cat ${openbao_dir}/config/psmdb-access.hcl

# enforce ownership to openbao user inside the container
sudo chown -vR 100:1000 ${openbao_dir}

# start openbao container with TLS
docker run -d --network ${net_name} --ip ${server_ip} --name openbao_${case_number} \
  --restart unless-stopped \
  --cap-add IPC_LOCK \
  -p 8200:8200 \
  -v ${openbao_dir}:/openbao \
  openbao/openbao:latest server -config=/openbao/config/openbao.hcl
# wait for initialization
until docker logs openbao_${case_number} 2>&1 | grep -q "cluster listener addresses synthesized"; do
  sleep 1
done
docker logs openbao_${case_number} 2>&1 | grep "cluster listener addresses synthesized"

# initialize OpenBao (required for non-dev mode)
op_init_output=$(docker exec -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt -e BAO_TOKEN=${BAO_TOKEN} openbao_${case_number} bao operator init -key-shares=1 -key-threshold=1 -format=json)
unseal_key=$(echo $op_init_output | jq -r .unseal_keys_b64[0])
BAO_TOKEN=$(echo $op_init_output | jq -r .root_token)
# save keys and token
echo ${unseal_key} | sudo tee ${openbao_dir}/unseal_key >/dev/null
echo ${BAO_TOKEN} | sudo tee ${openbao_dir}/root_token >/dev/null
# check
cat ${openbao_dir}/unseal_key
cat ${openbao_dir}/root_token
# enforce permissions
sudo chmod 400 ${openbao_dir}/unseal_key ${openbao_dir}/root_token

# define reusable long string for docker exec environment variables (defined only here because BAO_TOKEN had no value before)
docker_env_string="-e BAO_TOKEN=${BAO_TOKEN} -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt"
# check
echo "docker_env_string: ${docker_env_string}"

# unseal OpenBao
docker exec ${docker_env_string} openbao_${case_number} bao operator unseal ${unseal_key}

# enable KV-v2 secrets engine
docker exec ${docker_env_string} openbao_${case_number} bao secrets enable --version=2 -path=secret kv

# copy policy to container and apply
docker exec ${docker_env_string} openbao_${case_number} bao policy write psmdb-policy /openbao/config/psmdb-access.hcl
# check policy in container
docker exec ${docker_env_string} openbao_${case_number} bao policy read psmdb-policy

# create tokens for MongoDB nodes (one per replica set member)
for i in $( seq 1 ${replica_count} ); do
  token=$(docker exec ${docker_env_string} openbao_${case_number} bao token create -policy=psmdb-policy -format=json | jq -r .auth.client_token)
  echo -n "token for psmdb_${case_number}_${i}: "; echo ${token} | sudo tee ${docker_base_dir}/psmdb_${case_number}_${i}/token
  sudo chmod -v 400 ${docker_base_dir}/psmdb_${case_number}_${i}/token
  sudo chown -v 1001:1001 ${docker_base_dir}/psmdb_${case_number}_${i}/token
done
# check tokens
ls -lart ${docker_base_dir}/psmdb_${case_number}_*/token

# add openbao config in mongod.conf
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
  vault:
    serverName: ${server_ip}
    port: 8200
    secret: secret/data/rs-${case_number}/psmdb_${case_number}_${i}
    tokenFile: /mongodb/token
    serverCAFile: /mongodb/tls/ca.pem

setParameter:
  authenticationMechanisms: SCRAM-SHA-256
EOF
done
cat ${docker_base_dir}/psmdb_${case_number}_${i}/mongod.conf
# check files - size should be around 530
ls -lart ${docker_base_dir}/*/mongod.conf
# enforce ownership
sudo chown -vR 1001:1001 ${docker_base_dir}/*/mongod.conf

# restart psmdb containers
for i in $( seq ${replica_count} -1 1 ); do
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
  # verify encryption success
  echo -n "psmdb_${case_number}_${i}: "; until sudo grep -q "Encryption keys DB is initialized successfully" ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log; do
    sleep 1
  done
  sudo grep "Encryption keys DB is initialized successfully" ${docker_base_dir}/psmdb_${case_number}_${i}/log/mongod.log
done

# done

# extra

## unseal after restart
unseal_key=$(cat ${openbao_dir}/unseal_key)
BAO_TOKEN=$(cat ${openbao_dir}/root_token)
export BAO_TOKEN
docker exec -e BAO_TOKEN=${BAO_TOKEN} -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt openbao_${case_number} bao operator unseal ${unseal_key}

## test OpenBao is working
docker exec -e BAO_TOKEN=${BAO_TOKEN} -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt openbao_${case_number} bao status

## container logs
docker logs openbao_${case_number} -f

## check certificates from psmdb container
docker exec psmdb_${case_number}_1 openssl s_client -showcerts -servername ${server_ip} -connect ${server_ip}:8200 -CAfile /mongodb/tls/ca.pem

## shell into openbao
docker exec -u root -it openbao_${case_number} sh

## test kv operations
docker exec -e BAO_TOKEN=${BAO_TOKEN} -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt openbao_${case_number} bao kv put -mount=secret ${case_number}/test-key value=test123
docker exec -e BAO_TOKEN=${BAO_TOKEN} -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt openbao_${case_number} bao kv get -mount=secret ${case_number}/test-key
docker exec -e BAO_TOKEN=${BAO_TOKEN} -e BAO_ADDR=https://${server_ip}:8200 -e BAO_CACERT=/openbao/tls/ca.crt openbao_${case_number} bao kv delete -mount=secret ${case_number}/test-key
