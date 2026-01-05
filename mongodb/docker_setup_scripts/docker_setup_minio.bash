# Minio setup to run with PBM docker setup.

# create MongoDB containers
## ./docker_setup_psmdb_rs.bash
# setup PBM
## ./docker_setup_psmdb_pbm.bash

# reuse variables from previous scripts

# cleanup
docker rm -f minio_${case_number}
sudo rm -rf ${docker_base_dir}/minio_${case_number}

# initialize folder
mkdir -pv ${docker_base_dir}/minio_${case_number}

# not necessary if mongod process is started with my user, check pbm_setup
# sudo chown -R mongod. ${docker_base_dir}/minio_${case_number}

docker run -d \
   -p 9000:9000 \
   -p 9001:9001 \
   --name minio_${case_number} \
   -v ${docker_base_dir}/minio_${case_number}:/data \
   --network ${case_number}-net --ip "${net_prefix}.$(( port_counter + 32 ))" \
   -e "MINIO_ROOT_USER=ROOTNAME" \
   -e "MINIO_ROOT_PASSWORD=CHANGEME123" \
   quay.io/minio/minio server /data --console-address ":9001"

# set and print IP
minio_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' minio_${case_number})
echo "minio_ip: ${minio_ip}"

# set alias and create bucket
docker exec minio_${case_number} mc alias set myminio http://127.0.0.1:9000 ROOTNAME CHANGEME123
docker exec minio_${case_number} mc mb myminio/pbm-backup

# done

# extra

# tunneling
## another terminal - copy the IP from the variable
minio_ip="172.2.0.35"
ssh -L 9001:${minio_ip}:9001 <host-fqdn-or-ip>
## the session will be open and then use http://localhost:9001 in local browser
