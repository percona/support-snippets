#!/bin/bash
function trg_plugin() {
  echo $(mysql ${EXT_ARGV} -BNe "show engine innodb status \G" | grep 'History list length' | awk '{print $4}');
}