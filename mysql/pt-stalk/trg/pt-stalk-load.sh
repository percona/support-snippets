#!/bin/bash
trg_plugin() {
    echo `cat /proc/loadavg |awk '{ print $1 }' |awk -F'.' '{ print $1 }'`
}
