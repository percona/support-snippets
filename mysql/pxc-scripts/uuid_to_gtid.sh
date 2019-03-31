#!/bin/bash

# USAGE 
# bash uuid_to_gtid.sh $UUID
# take the cluster UUID from wsrep_cluster_state_uuid status variable, like:
# bash uuid_to_gtid.sh $(mysql -BN -e "select VARIABLE_VALUE from performance_schema.global_status where VARIABLE_NAME='wsrep_cluster_state_uuid'")

rm -fr /tmp/myHEX?

for i in {1..5}; 
		do echo $1|awk -F '-' "{print toupper(\$$i)}" > /tmp/myHEX$i 
done

	a1=$(echo "obase=16;ibase=16;FFFFFFFF-$(cat /tmp/myHEX1)"|bc)
	a2=$(echo "obase=16;ibase=16;FFFF-$(cat /tmp/myHEX2)"|bc)
	a3=$(echo "obase=16;ibase=16;FFFF-$(cat /tmp/myHEX3)"|bc)
	a4=$(echo "obase=16;ibase=16;FFFF-$(cat /tmp/myHEX4)"|bc)
	a5=$(echo "obase=16;ibase=16;FFFFFFFFFFFF-$(cat /tmp/myHEX5)"|bc)

echo $a1-$a2-$a3-$a4-$a5|tr '[:upper:]' '[:lower:]'
