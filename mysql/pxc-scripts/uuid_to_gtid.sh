#!/bin/bash

# USAGE 
# bash uuid_to_gtid.sh $UUID
# take the cluster UUID from wsrep_cluster_state_uuid status variable, like:
# bash uuid_to_gtid.sh $(mysql -BN -e "select VARIABLE_VALUE from performance_schema.global_status where VARIABLE_NAME='wsrep_cluster_state_uuid'")

IFS=$'-';
arr=()
for i in $1; do 
	arr+=($i); 
done

a1=$(printf '%x' $((0xFFFFFFFF - 0x${arr[0]})))
a2=$(printf '%x' $((0xFFFF - 0x${arr[1]})))
a3=$(printf '%x' $((0xFFFF - 0x${arr[2]})))
a4=$(printf '%x' $((0xFFFF - 0x${arr[3]})))
a5=$(printf '%x' $((0xFFFFFFFFFFFF - 0x${arr[4]})))

echo $a1-$a2-$a3-$a4-$a5|tr '[:upper:]' '[:lower:]'
