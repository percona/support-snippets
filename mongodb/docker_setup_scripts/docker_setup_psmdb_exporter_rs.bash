# mongodb-exporter setup to run with docker replica set

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash

# reuse variables from previous scripts
exporter_version="0.47.1"
metrics_base_dir="${docker_base_dir}/metrics"

# cleanup => errors are expected if the containers are not running or there are other containers using the network
for i in $( seq 1 ${replica_count} ); do
  docker rm -f exporter_${case_number}_${i}
done
docker network rm ${net_name}
sudo rm -rf ${metrics_base_dir}

# launch exporter containers
exporter_port=9217
for i in $( seq 1 ${replica_count} ); do
  docker run -d --name=exporter_${case_number}_${i} --network ${net_name} --ip "${net_prefix}.$(( port_counter + 32 ))" -p $(( exporter_port + i )):9216 percona/mongodb_exporter:${exporter_version} --mongodb.uri="mongodb://testuser:testpwd@${!varname}:27017/admin" --collect-all # --compatible-mode
  let port_counter++
done

# done

# extra
## list containers
docker ps | grep ${case_number}

## logs
docker logs exporter_${case_number}_${i}

## set and print IPs
for i in $( seq 1 ${replica_count} ); do
  declare exporter_ip_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_${i} 2>/dev/null)
  varname=exporter_ip_${i}
  echo "${varname}: "${!varname}
done

# scrape
## initialize folder
mkdir -pv ${metrics_base_dir}
rm -fv ${metrics_base_dir}/*.prom

## scrape metrics with curl. It is normal if the first scrape generates files with less data. Run it again.
for i in $( seq 1 ${replica_count} ); do
  declare exporter_ip_${i}=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' exporter_${case_number}_${i} 2>/dev/null)
  varname=exporter_ip_${i}
  curl http://${!varname}:9216/metrics > ${metrics_base_dir}/${varname}.$(date +%Y%m%d_%H%M%S).prom
done

## list metrics files
ls -lart ${metrics_base_dir}/*.prom

## grep metric
grep -ni mongodb_ss_wt_concurrentTransactions_totalTickets ${metrics_base_dir}/*.prom
