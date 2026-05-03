#!/bin/bash
trg_plugin() {
  current_sample_tmp_file="/tmp/pt-stalk-flow-control-rate.dat";
  current_sample=$(mysql ${EXT_ARGV} -BNe "SHOW GLOBAL STATUS LIKE 'wsrep_flow_control_paused_ns'" | awk '{ print $2 }');
  if [ -f "$current_sample_tmp_file" ]
  then
    previous_sample=$(cat $current_sample_tmp_file);
    echo "$current_sample" > $current_sample_tmp_file;
    echo $(( (current_sample - previous_sample) / 1000 / 1000 )) | awk '{ print $1 }';
  else
    echo "$current_sample" > $current_sample_tmp_file;
    echo 0;
  fi
}
