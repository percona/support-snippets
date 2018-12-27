#!/bin/bash
INTERFACE=$1
if [[ "$INTERFACE" == "" ]]
then
  INTERFACE='eth0'
fi

echo "Using ${INTERFACE} as network interface"

while true; do {
  duration_s=$(shuf -i 5-7 -n 1);
  latency=$(shuf -i 2500-3999 -n 1);
  loss=$(shuf -i 40-60 -n 1);


  if [[ $((${RANDOM} % 3)) -eq 0 ]]; then {
    echo "$(date) will sleep for ${duration_s} seconds while adding ${latency}ms of latency and ${loss}% of packet loss"
    tc qdisc add dev ${INTERFACE} root netem delay ${latency}ms loss ${loss}%;
    sleep $duration_s
    tc qdisc del dev ${INTERFACE} root netem;
    echo "$(date) Done"
  } fi;
  echo "$(date) Sleeping for 5 seconds to allow node to rejoin"
  echo ""
  sleep 5;
} done;
