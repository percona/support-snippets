# mongodb-exporter setup to run with docker sharded cluster

# create MongoDB containers
## ./docker_setup_psmdb_sharded.bash

# reuse variables from previous scripts
exporter_version="0.47.1"
metrics_base_dir="${docker_base_dir}/metrics"

# cleanup => errors are expected if the containers are not running or there are other containers using the network
for i in $( seq 1 ${replica_count} ); do
  docker rm -f exporter_${case_number}_config_${i}
  for j in $( seq 1 ${shard_count} ); do
    docker rm -f exporter_${case_number}_shard${j}_${i}
  done
done
docker rm -f exporter_${case_number}_mongos_1
docker network rm ${net_name}
sudo rm -rf ${metrics_base_dir}

# launch exporter containers
exporter_port=9217
## config
for i in $( seq 1 ${replica_count} ); do
  varname=psmdb_ip_config_${i}
  docker run -d --name=exporter_${case_number}_config_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 32 ))" -p $(( exporter_port + port_counter )):9216 percona/mongodb_exporter:${exporter_version} --mongodb.uri="mongodb://rs_testuser:testpwd@${!varname}:27017/admin" --collect-all # --compatible-mode
  let port_counter++
done
## shards
for j in $( seq 1 ${shard_count} ); do
  for i in $( seq 1 ${replica_count} ); do
    varname=psmdb_ip_shard${j}_${i}
    docker run -d --name=exporter_${case_number}_shard${j}_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 32 ))" -p $(( exporter_port + port_counter )):9216 percona/mongodb_exporter:${exporter_version} --mongodb.uri="mongodb://rs_testuser:testpwd@${!varname}:27017/admin" --collect-all # --compatible-mode
    let port_counter++
  done
done
## mongos
psmdb_ip_mongos_1=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' psmdb_${case_number}_mongos_1)
docker run -d --name=exporter_${case_number}_mongos_1 --network ${net_name} --ip "${net_prefix}.$(( port_counter + 32 ))" -p 9216:9216 percona/mongodb_exporter:${exporter_version} --mongodb.uri="mongodb://testuser:testpwd@${psmdb_ip_mongos_1}:28017/admin" --collect-all # --compatible-mode

# done

# extra
## logs - if needed
docker logs exporter_${case_number}_mongos_1
docker logs exporter_${case_number}_config_1
docker logs exporter_${case_number}_shard1_1
docker logs exporter_${case_number}_shard2_1

# set and print IPs
## config
for i in $( seq 1 ${replica_count} ); do
  declare exporter_ip_config_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_config_${i})
  varname=exporter_ip_config_${i}
  echo "${varname}: "${!varname}
done
## shards
for j in $( seq 1 ${shard_count} ); do
  for i in $( seq 1 ${replica_count} ); do
    declare exporter_ip_shard${j}_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_shard${j}_${i})
    varname=exporter_ip_shard${j}_${i}
    echo "${varname}: "${!varname}
  done
  echo ""
done
## mongos
declare exporter_ip_mongos_1=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_mongos_1)
varname=exporter_ip_mongos_1
echo "${varname}: "${!varname}




# scrape
## initialize folder
mkdir -pv ${metrics_base_dir}
rm -fv ${metrics_base_dir}/*.prom


# set and print IPs
## config
for i in $( seq 1 ${replica_count} ); do
  declare exporter_ip_config_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_config_${i})
  varname=exporter_ip_config_${i}
  echo "${varname}: "${!varname}
  curl http://${!varname}:9216/metrics > ${metrics_base_dir}/${varname}.$(date +%Y%m%d_%H%M%S).prom
done
## shards
for j in $( seq 1 ${shard_count} ); do
  for i in $( seq 1 ${replica_count} ); do
    declare exporter_ip_shard${j}_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_shard${j}_${i})
    varname=exporter_ip_shard${j}_${i}
    curl http://${!varname}:9216/metrics > ${metrics_base_dir}/${varname}.$(date +%Y%m%d_%H%M%S).prom
  done
done
## mongos
declare exporter_ip_mongos_1=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_mongos_1)
varname=exporter_ip_mongos_1
curl http://${!varname}:9216/metrics > ${metrics_base_dir}/${varname}.$(date +%Y%m%d_%H%M%S).prom

## list metrics files
ls -lart ${metrics_base_dir}/*.prom

## grep metric
grep -ni mongodb_ss_wt_concurrentTransactions_totalTickets ${metrics_base_dir}/*.prom
