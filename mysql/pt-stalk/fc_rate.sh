#!/bin/bash
# ./pt-stalk --daemonize --variable=flow_control --function=/tmp/fc_rate.sh --threshold=350 --cycles=5 --iterations=5 --run-time=60 --sleep=120 
function trg_plugin() {
   tmp_data="/tmp/pt-flow-control.dat";
   current_sample=$(mysql ${EXT_ARGV} -BNe "SHOW GLOBAL STATUS LIKE 'wsrep_flow_control_paused_ns'" | awk '{ print $2 }');
   if [ -f "$tmp_data" ]
   then
        previous_sample=$(cat $tmp_data);
        echo "$current_sample" > $tmp_data;
        echo $(( ($current_sample - $previous_sample) / 1000 / 1000 )) | awk '{ print $1 }';
   else
        echo "$current_sample" > $tmp_data;
        echo 0;
   fi
}
