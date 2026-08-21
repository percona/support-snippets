#!/usr/bin/env bash
# Smoke-test L4..L10 like a real candidate would: spawn the level, verify
# check.sh fails (initial broken state), apply the fix via docker exec,
# verify check.sh passes. Uses a separate network and "smoketest-" name
# prefix so it does not disturb anything on interview_net.
set -uo pipefail

NET=smoketest_net
PREFIX=smoketest-

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; RESET='\033[0m'
ok()   { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
fail() { printf "${RED}✗ %s${RESET}\n" "$*"; }
info() { printf "${YELLOW}… %s${RESET}\n" "$*"; }

cleanup() {
    docker ps -aq --filter "name=^/${PREFIX}" | xargs -r docker rm -f >/dev/null 2>&1 || true
}
trap cleanup EXIT

ensure_net() {
    docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
}

spawn() {
    local level=$1; shift
    local nodes=("$@")
    local img="interview/exercise-$(printf %02d "$level")"
    local peers
    peers=$(IFS=,; echo "${nodes[*]}")
    cleanup
    local i=0
    for n in "${nodes[@]}"; do
        docker run -d --rm \
            --name "${PREFIX}${n}" --hostname "$n" \
            --network "$NET" \
            --privileged --cgroupns=host \
            --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
            -e LEVEL="$level" -e NODE_NAME="$n" -e NODE_INDEX="$i" \
            -e NODE_PEERS="$peers" \
            "$img" >/dev/null
        i=$((i+1))
    done
}

wait_for_mongod() {
    local node=$1
    for _ in $(seq 1 180); do
        docker exec "${PREFIX}${node}" mongosh --quiet --eval 'db.adminCommand({ping:1}).ok' \
            mongodb://127.0.0.1:27017/admin >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

wait_for_rs_primary() {
    local node=$1
    for _ in $(seq 1 240); do
        local s
        s=$(docker exec "${PREFIX}${node}" mongosh --quiet --eval 'rs.status().myState' 2>/dev/null | tr -d '\r\n ')
        [ "$s" = "1" ] && return 0
        sleep 2
    done
    return 1
}

run_check() {
    docker exec "${PREFIX}node1" /usr/local/bin/check.sh >/dev/null 2>&1
}

mongo_on() {
    local node=$1; shift
    docker exec "${PREFIX}${node}" mongosh --quiet --eval "$*" mongodb://127.0.0.1:27017/admin
}

result_summary=()

run_level() {
    local level=$1 desc=$2
    info "L${level}: ${desc}"
    case "$level" in
        1) spawn "$level" node1
           sleep 12  # mongod is intentionally DOWN (bad bindIp) — don't wait for it
           ;;
        2) spawn "$level" node1
           wait_for_mongod node1 || { fail "mongod never came up"; result_summary+=("L${level}: SETUP FAIL"); return; }
           ;;
        3) spawn "$level" node1 node2 node3
           wait_for_mongod node1 || { fail "node1 mongod never came up"; result_summary+=("L${level}: SETUP FAIL"); return; }
           wait_for_mongod node2 || { fail "node2 mongod never came up"; result_summary+=("L${level}: SETUP FAIL"); return; }
           # node3 has PSMDB uninstalled by design — candidate must install it
           sleep 5
           ;;
        9) spawn "$level" node1; wait_for_mongod node1 || { fail "mongod never came up"; result_summary+=("L${level}: SETUP FAIL"); return; } ;;
        *) spawn "$level" node1 node2 node3
           wait_for_mongod node1 || { fail "node1 mongod never came up"; result_summary+=("L${level}: SETUP FAIL"); return; }
           wait_for_rs_primary node1 || { fail "RS never elected a primary"; result_summary+=("L${level}: SETUP FAIL"); return; }
           sleep 10  # let post-init scripts (data load, failpoint, drops) settle
           ;;
    esac

    if run_check; then
        fail "check.sh PASSED in initial broken state — setup didn't break it"
        result_summary+=("L${level}: SETUP-NOT-BROKEN")
    else
        ok "initial state correctly fails check.sh"
    fi

    info "applying fix"
    case "$level" in
        1)
            # Restore a valid bindIp, restart mongod, then write the current
            # open-connection count to answer.txt.
            docker exec "${PREFIX}node1" bash -c '
                sed -i "s/^[[:space:]]*bindIp:.*/  bindIp: 0.0.0.0/" /etc/mongod.conf
                systemctl restart mongod' >/dev/null 2>&1
            wait_for_mongod node1 || true
            docker exec "${PREFIX}node1" bash -c '
                c=$(mongosh --quiet --eval "print(db.serverStatus().connections.current)" \
                    mongodb://127.0.0.1:27017/admin | tr -cd "0-9")
                echo "$c" > /home/candidate/answer.txt'
            ;;
        2)
            docker exec "${PREFIX}node1" bash -c '
                set -e
                tar xzf /tmp/company.json.tar.gz -C /tmp
                mongoimport --quiet --db percona --collection company \
                    --file /tmp/company.json' >/dev/null 2>&1
            ;;
        3)
            # node3: install PSMDB live from the Percona repo (the level's
            # raison d'être), then configure replSetName on all three + initiate.
            info "  installing PSMDB on node3 (live dnf — may take a minute)"
            docker exec "${PREFIX}node3" bash -c '
                dnf -y install percona-server-mongodb percona-server-mongodb-shell \
                    >/dev/null 2>&1
                systemctl daemon-reload' \
                || { fail "dnf install on node3 failed"; result_summary+=("L${level}: ${RED}FAIL (install)${RESET}"); cleanup; return; }
            for n in node1 node2 node3; do
                docker exec "${PREFIX}${n}" bash -c '
                    grep -q "^replication:" /etc/mongod.conf || \
                        printf "\nreplication:\n  replSetName: interview\n" >> /etc/mongod.conf
                    # node3 fresh install may default bindIp to 127.0.0.1
                    sed -i "s/^[[:space:]]*bindIp:.*/  bindIp: 0.0.0.0/" /etc/mongod.conf
                    systemctl enable mongod >/dev/null 2>&1 || true
                    systemctl restart mongod' >/dev/null 2>&1
            done
            wait_for_mongod node1 || true
            wait_for_mongod node2 || true
            wait_for_mongod node3 || true
            docker exec "${PREFIX}node1" mongosh --quiet --eval '
                rs.initiate({_id:"interview", members:[
                    {_id:0, host:"node1:27017"},
                    {_id:1, host:"node2:27017"},
                    {_id:2, host:"node3:27017"}]})' >/dev/null 2>&1
            wait_for_rs_primary node1 || true
            sleep 5
            ;;
        4)
            mongo_on node1 'cfg = rs.conf();
              cfg.members.forEach(m => { m.priority = m.host.startsWith("node1:") ? 2 : 1; });
              rs.reconfig(cfg, {force: true});'
            # Wait for node1 to win the election.
            for _ in $(seq 1 60); do
                s=$(docker exec "${PREFIX}node1" mongosh --quiet --eval 'rs.status().myState' 2>/dev/null | tr -d '\r\n ')
                [ "$s" = "1" ] && break
                sleep 2
            done
            ;;
        5)
            docker exec "${PREFIX}node3" mongosh --quiet \
                --host node3 --port 27017 \
                --eval 'db.adminCommand({replSetResizeOplog: 1, size: 5120})' >/dev/null 2>&1
            ;;
        6)
            mongo_on node1 'db.getSiblingDB("percona").company.createIndex(
                {industry: 1, country: 1, employees: -1, founded: 1})' >/dev/null
            ;;
        7)
            docker exec "${PREFIX}node3" mongosh --quiet --eval \
                'db.fsyncUnlock()' >/dev/null 2>&1
            sleep 8  # let lag drain
            ;;
        8)
            # Four layered faults: drop the three conflicting storage lines and
            # fix the replSetName typo (lnterview -> interview), then start.
            docker exec "${PREFIX}node3" bash -c '
                sed -i -e "/^  directoryPerDB: true$/d" \
                       -e "/^  engine: mmapv1$/d" \
                       -e "/^      directoryForIndexes: true$/d" \
                       -e "s/replSetName: lnterview/replSetName: interview/" /etc/mongod.conf
                systemctl start mongod
            '
            for _ in $(seq 1 90); do
                docker exec "${PREFIX}node3" mongosh --quiet --eval 'db.adminCommand({ping:1}).ok' >/dev/null 2>&1 && break
                sleep 2
            done
            sleep 5  # give RS a moment to mark node3 healthy again
            ;;
        9)
            # The answer is the version inside the CUSTOMER FTDC chunk at
            # /opt/customer-ftdc/metrics.bson — NOT the live mongod's own
            # diagnostic.data (that is the whole point of the level).
            docker exec "${PREFIX}node1" bash -c '
                set -e
                v=$(bsondump --quiet /opt/customer-ftdc/metrics.bson 2>/dev/null | head -1 | jq -r ".doc.buildInfo.version")
                echo "$v" > /home/candidate/answer.txt
            '
            ;;
        10)
            docker exec "${PREFIX}node1" mongorestore --quiet \
                --host node1 --port 27017 /backups >/dev/null 2>&1
            ;;
    esac

    if run_check; then
        ok "fix worked, check.sh PASSED"
        result_summary+=("L${level}: ${GREEN}OK${RESET}")
    else
        fail "fix did not satisfy check.sh"
        result_summary+=("L${level}: ${RED}FAIL${RESET}")
    fi
    cleanup
}

ensure_net

# Level descriptions. Run all by default, or pass specific levels:
#   ./smoketest.sh 8 9    # only re-test L8 and L9
declare -A DESC=(
    [1]="restore bindIp + report connections.current to answer.txt"
    [2]="mongoimport company.json into percona.company"
    [3]="install PSMDB on node3, then build the 3-node replica set"
    [4]="node1 priority raised, wins election"
    [5]="node3 oplog grows from 990MB to 5GB"
    [6]="ESR compound index on percona.company (no COLLSCAN, no SORT)"
    [7]="release the leftover fsyncLock on node3"
    [8]="fix 4 faults in node3 mongod.conf (storage + replSetName typo)"
    [9]="extract mongod version from customer FTDC into answer.txt"
    [10]="mongorestore /backups"
)

if [ "$#" -gt 0 ]; then
    levels=("$@")
else
    levels=(1 2 3 4 5 6 7 8 9 10)
fi

for lvl in "${levels[@]}"; do
    run_level "$lvl" "${DESC[$lvl]:-level $lvl}"
done

echo
echo "==== Summary ===="
for line in "${result_summary[@]}"; do
    printf "  %b\n" "$line"
done
