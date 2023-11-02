#!/bin/bash

INTERFACE=${1:-eth0};
DURATION_RANGE=${2:-15-20};
LATENCY_RANGE=${3:-1500-3999};
LOSS_RANGE=${4:-20-30};

echo "     INTERFACE: ${INTERFACE}";
echo "DURATION_RANGE: ${DURATION_RANGE}";
echo " LATENCY_RANGE: ${LATENCY_RANGE}";
echo "    LOSS_RANGE: ${LOSS_RANGE}";

function signal_handler() {
  echo -e "[$(date)] Caught SIGINT!";
  echo -e "[$(date)] Removing qdisc from ${INTERFACE}...";
  tc qdisc del dev ${INTERFACE} root netem;
  echo -e "[$(date)] Done!";
  exit;
}
trap signal_handler SIGINT;

while true; do {
  duration_s=$(shuf -i ${DURATION_RANGE} -n 1);
  latency=$(shuf -i ${LATENCY_RANGE} -n 1);
  loss=$(shuf -i ${LOSS_RANGE} -n 1);

  echo "[$(date)] Current qdisc for ${INTERFACE}:";
  tc qdisc show dev ${INTERFACE};

  echo -e "[$(date)] Adding ${latency}ms of latency and ${loss}% of packet loss...";
  tc qdisc add dev ${INTERFACE} root netem delay "${latency}"ms loss "${loss}"%;

  echo -e "[$(date)] Sleeping for ${duration_s} seconds...";
  sleep "${duration_s}";

  echo -e "[$(date)] Removing qdisc from ${INTERFACE}...";
  tc qdisc del dev ${INTERFACE} root netem;

  echo -e "[$(date)] Done!";

  echo -e "[$(date)] Sleeping for 5 seconds to allow node to rejoin\n=======================================================================================================\n";
  sleep 5;
} done;
