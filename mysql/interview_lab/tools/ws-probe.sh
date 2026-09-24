#!/usr/bin/env bash
# Put up a harmless, read-only terminal at /term/wstest/ so a candidate can
# prove, the day before, that their network lets a browser terminal through.
#
#   ./tools/ws-probe.sh start     # then send them http://<IP>/term/wstest/
#   ./tools/ws-probe.sh stop
#
# Run it on the lab server. The embedded terminal is a WebSocket, and corporate
# proxies that strip the Upgrade header let every other page load while the
# terminal stays black or stuck on "Starting exercise". Finding that at T-0
# costs the candidate twenty minutes of a timed test; finding it the day before
# costs nothing.
#
# The probe is deliberately not the lab: nothing is started, no clock runs, and
# the terminal is read-only (ttyd without -W), so the candidate sees a prompt
# render and can type nothing. It is a plain bash in the base image with no
# fault planted, so nothing about any question leaks. nginx only routes
# /term/<node>/ to mysql-exercise-current-<node>, hence the container name; the
# controller's next spawn or reset removes it as well if you forget to.
set -euo pipefail

NODE=wstest
NAME="mysql-exercise-current-${NODE}"
IMAGE=mysqlinterview/exercise-base

# The network nginx reaches exercise containers on: whatever the running
# controller uses, else the compose default.
net=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' mysql-controller 2>/dev/null \
      | sed -n 's/^INTERVIEW_NETWORK=//p' | head -1)
net="${net:-mysql_interview_net}"

case "${1:-}" in
    start)
        docker rm -f "$NAME" >/dev/null 2>&1 || true
        docker run -d --rm --name "$NAME" --hostname "$NODE" --network "$net" \
            --entrypoint /usr/local/bin/ttyd "$IMAGE" \
            -p 7681 -i 0.0.0.0 -b "/term/${NODE}/" \
            -t disableLeaveAlert=true -t titleFixed="connection test" /bin/bash >/dev/null
        cat <<EOF
Probe is up on $net. Send the candidate (with the candidate login):

    http://<this box's public IP>/term/${NODE}/

They should see a prompt ending in "${NODE}" within a few seconds. Typing does
nothing, by design. If they see "Starting exercise" forever or a black page
while http://<IP>/ itself loads, their network is blocking WebSockets: a phone
hotspot or a personal network is the usual way out. Note that a black terminal
is also what their proxy would do on interview day.

When done:  ./tools/ws-probe.sh stop
EOF
        ;;
    stop)
        docker rm -f "$NAME" >/dev/null 2>&1 && echo "probe removed" || echo "no probe was running"
        ;;
    *)
        echo "usage: ./tools/ws-probe.sh start|stop" >&2
        exit 1
        ;;
esac
