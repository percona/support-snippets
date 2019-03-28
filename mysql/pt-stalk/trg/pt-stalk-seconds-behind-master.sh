#!/bin/bash
trg_plugin() {
   mysql $EXT_ARGV -Ee "SHOW SLAVE STATUS" | grep "Seconds_Behind_Master" | awk '{ print $2 }'
}
