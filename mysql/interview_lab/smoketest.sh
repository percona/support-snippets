#!/usr/bin/env bash
# Smoke-test every level like a real candidate would: spawn the level, verify
# check.sh fails (initial broken state), apply the known-good fix via docker
# exec, verify check.sh passes. Uses a separate network and a "smoketest-"
# name prefix so it does not disturb anything on mysql_interview_net.
#
# Two further, clearly separated sections follow. Negative cases assert that a
# wrong or incomplete fix is rejected (three false passes survived until an
# audit because nothing ever checked that). Security guarantees assert what the
# lab's design rests on and no question test touches: no internet egress from
# a node, no route from a node to the controller, a transcript really written
# for every shell, and the paste guard really injected by nginx. Each of those
# has broken silently before while all 11 questions passed.
#
#   ./smoketest.sh                 all 11 levels, the negative cases, then security
#   ./smoketest.sh 3 6 8           just those levels
#   ./smoketest.sh negative        just the "a wrong fix must not pass" cases
#   ./smoketest.sh security        just the security section
#   ./smoketest.sh 8 security      any combination
#
# Exit status is non-zero when anything failed, so it can gate a deploy.
#
# This file is also the answer key. Read it before you interview anyone, and
# never let it reach the server: deploy.sh excludes it, and
# tools/remote-smoketest.sh streams it over ssh for the run instead.
set -uo pipefail

# tools/remote-smoketest.sh streams this file over ssh and runs it from a file
# descriptor, so $0 is /dev/fd/N rather than a path in the lab directory. Only
# chdir when $0 really lives there; otherwise trust the caller's cwd.
[ -f "$(dirname "$0")/build.sh" ] && cd "$(dirname "$0")"
if [ ! -f build.sh ] || [ ! -d exercises ]; then
    echo "smoketest.sh: run it from the lab directory (exercises/ not found in $PWD)" >&2
    exit 2
fi

NET=mysql_smoketest_net
PREFIX=smoketest-
# Own transcript volume, mounted the same way the controller mounts the real
# one. Without this the containers have no /var/log/history, so transcripts,
# keystroke timing and the artifacts check.sh preserves (the written report,
# the submitted query) are silently never written — and the suite would pass
# while that whole path was broken. Separate from the lab's volume so a test
# run cannot pollute real candidate evidence.
HISTVOL=mysql-smoketest-history

# The live lab's pieces, used only by the security section.
CONTROLLER=mysql-controller
NGINX=mysql-nginx
# nginx routes /term/<node>/ to mysql-exercise-current-<node>, so the paste
# guard probe has to wear that prefix. The node name is one no question uses,
# so it can never collide with a real exercise container.
GUARD_NODE=smoketestguard
GUARD_CONTAINER="mysql-exercise-current-${GUARD_NODE}"
PROBE="${PREFIX}secprobe"

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; RESET='\033[0m'
ok()   { printf "${GREEN}\xe2\x9c\x93 %s${RESET}\n" "$*"; }
fail() { printf "${RED}\xe2\x9c\x97 %s${RESET}\n" "$*"; }
info() { printf "${YELLOW}\xe2\x80\xa6 %s${RESET}\n" "$*"; }

cleanup() {
    docker ps -aq --filter "name=^/${PREFIX}" | xargs -r docker rm -f >/dev/null 2>&1 || true
    # The guard probe cannot carry the smoketest prefix (see GUARD_NODE), so
    # it is removed by name.
    docker rm -f "$GUARD_CONTAINER" >/dev/null 2>&1 || true
}
# The history volume holds the model Q9 query and Q11 report the fixes write.
# A candidate is root in a privileged container and can reach the host disk,
# so it goes when the suite does, not when the next run starts.
trap 'cleanup; docker volume rm "$HISTVOL" >/dev/null 2>&1 || true' EXIT

ensure_net() {
    docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
    docker volume rm "$HISTVOL" >/dev/null 2>&1 || true
    docker volume create "$HISTVOL" >/dev/null
}

level_dir() {
    local n; n=$(printf %02d "$1")
    for d in exercises/${n}-*/; do [ -d "$d" ] && { echo "${d%/}"; return; }; done
}

# Extra `docker run` arguments for the next spawn (the transcript probe passes
# the controller's HISTDIR this way). Reset after every spawn.
SPAWN_EXTRA=()

spawn() {
    local level=$1; shift
    local nodes=("$@")
    local img="mysqlinterview/exercise-$(printf %02d "$level")"
    local peers; peers=$(IFS=,; echo "${nodes[*]}")
    cleanup
    local i=0
    for n in "${nodes[@]}"; do
        docker run -d --rm \
            --name "${PREFIX}${n}" --hostname "$n" \
            --network "$NET" \
            --privileged --cgroupns=host \
            --memory 1g --memory-swap 1g \
            --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
            -v "$HISTVOL":/var/log/history \
            -e LEVEL="$level" -e NODE_NAME="$n" -e NODE_INDEX="$i" \
            -e NODE_PEERS="$peers" \
            ${SPAWN_EXTRA[@]+"${SPAWN_EXTRA[@]}"} \
            "$img" >/dev/null
        i=$((i+1))
    done
    SPAWN_EXTRA=()
}

# A question is ready when interview-setup has finished, which is exactly when
# the candidate gets a terminal: ttyd runs After=interview-setup.service. A fixed
# sleep instead let a slow setup finish AFTER the fix had been applied, and on a
# loaded box Q6's index drop then deleted the correct index the suite had just
# built. It is a oneshot with RemainAfterExit, so "active" or "failed" means
# done; "inactive" (not started yet) and "activating" (running) mean wait.
wait_for_setup() {
    local node=$1 st
    for _ in $(seq 1 180); do
        st=$(docker exec "${PREFIX}${node}" systemctl is-active interview-setup 2>/dev/null)
        case "$st" in active|failed) return 0 ;; esac
        sleep 1
    done
    return 1
}

wait_for_mysqld() {
    local node=$1
    for _ in $(seq 1 240); do
        docker exec "${PREFIX}${node}" mysqladmin --protocol=socket ping >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# Wait for repl-bootstrap to finish wiring the topology. We watch node1's
# bootstrap log rather than a specific node's health: questions 7 and 8
# deliberately break node3 right after it joins, so polling node3 races the
# setup hook and times out on a server that is down by design.
wait_for_topology() {
    for _ in $(seq 1 180); do
        docker exec "${PREFIX}node1" \
            grep -q 'source=' /var/log/repl-bootstrap.log 2>/dev/null && return 0
        sleep 2
    done
    return 1
}

# check.sh is not baked into the image (that is the point), so the smoke test
# injects it the same way the controller does.
run_check() {
    local level=$1 d
    d=$(level_dir "$level")
    # Feed the grader in on stdin: /tmp is a tmpfs mount, so copying a file
    # in would land under the mount where exec cannot see it.
    docker exec -i "${PREFIX}node1" bash -s < "${d}/check.sh" >/dev/null 2>&1
}

# stdin is closed explicitly: `mysql -e` never reads it, but `docker exec -i`
# still attaches whatever stdin this suite was started with and would drain
# it into a process that has already exited.
mysql_on() { local node=$1; shift; docker exec -i "${PREFIX}${node}" mysql -uroot -e "$*" </dev/null; }

repoint() {  # repoint <node> at <source>
    mysql_on "$1" "
      STOP REPLICA;
      CHANGE REPLICATION SOURCE TO SOURCE_HOST='$2', SOURCE_PORT=3306,
        SOURCE_USER='repl', SOURCE_PASSWORD='repl',
        SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;
      START REPLICA;
      SET GLOBAL super_read_only=ON;" >/dev/null 2>&1
}

result_summary=()
sec_summary=()
failures=0

run_level() {
    local level=$1 desc=$2
    info "L${level}: ${desc}"
    case "$level" in
        1) spawn "$level" node1
           sleep 25  # mysqld is intentionally DOWN (bad bind-address)
           ;;
        2|5|6|9|10|11)
           spawn "$level" node1
           wait_for_mysqld node1 || { fail "mysqld never came up"; result_summary+=("L${level}: SETUP FAIL"); failures=$((failures+1)); return; }
           wait_for_setup node1 || { fail "setup never finished"; result_summary+=("L${level}: SETUP FAIL"); failures=$((failures+1)); return; }
           sleep 25  # background work some setups still start (Q11's seeding) needs time too
           ;;
        3) spawn "$level" node1 node2 node3
           wait_for_mysqld node1 || { fail "node1 mysqld never came up"; result_summary+=("L${level}: SETUP FAIL"); failures=$((failures+1)); return; }
           wait_for_mysqld node2 || { fail "node2 mysqld never came up"; result_summary+=("L${level}: SETUP FAIL"); failures=$((failures+1)); return; }
           # node3 has Percona Server uninstalled by design
           sleep 5
           ;;
        *) spawn "$level" node1 node2 node3
           wait_for_mysqld node1 || { fail "node1 mysqld never came up"; result_summary+=("L${level}: SETUP FAIL"); failures=$((failures+1)); return; }
           wait_for_topology || { fail "replication topology never came up"; result_summary+=("L${level}: SETUP FAIL"); failures=$((failures+1)); return; }
           sleep 20  # let post-bootstrap scripts (data load, lock, faults) settle
           ;;
    esac

    if run_check "$level"; then
        fail "check.sh PASSED in the initial broken state — setup didn't break it"
        result_summary+=("L${level}: SETUP-NOT-BROKEN")
        failures=$((failures+1))
    else
        ok "initial state correctly fails check.sh"
    fi

    info "applying fix"
    case "$level" in
        1)
            docker exec "${PREFIX}node1" bash -c '
                sed -i "s/^bind-address.*/bind-address             = 0.0.0.0/" /etc/my.cnf
                systemctl restart mysqld' >/dev/null 2>&1
            wait_for_mysqld node1 || true
            sleep 15  # let the application pool reconnect after the restart
            docker exec "${PREFIX}node1" bash -c '
                c=$(mysql -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE USER=\"appuser\";" | tr -cd "0-9")
                echo "$c" > /home/candidate/answer.txt'
            ;;
        2)
            # Extracted on disk under the candidate's home, next to where
            # setup.sh stages the dump. /tmp is a tmpfs charged to the 1 GB
            # memory cap, and the extracted dump there can OOM-kill mysqld
            # mid-import — the very failure the staging path was moved to avoid.
            docker exec "${PREFIX}node1" bash -c '
                set -e
                mkdir -p /home/candidate/emp
                tar xzf /home/candidate/employees-db.tar.gz -C /home/candidate/emp
                cd /home/candidate/emp && mysql -uroot < employees.sql' >/dev/null 2>&1
            ;;
        3)
            info "  installing Percona Server on node3 (from the image's local repo)"
            docker exec "${PREFIX}node3" bash -c '
                dnf -y install percona-server-server percona-server-client >/dev/null 2>&1
                systemctl daemon-reload
                systemctl enable --now mysqld' \
                || { fail "dnf install on node3 failed"; result_summary+=("L${level}: FAIL (install)"); failures=$((failures+1)); cleanup; return; }
            wait_for_mysqld node3 || true
            sleep 5
            repoint node2 node1
            repoint node3 node1
            sleep 8
            ;;
        4)
            mysql_on node1 "STOP REPLICA; RESET REPLICA ALL; SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;" >/dev/null 2>&1
            repoint node2 node1
            repoint node3 node1
            sleep 10
            ;;
        5)
            docker exec "${PREFIX}node1" bash -c '
                set -e
                cp /opt/recovered/titles.ibd /var/lib/mysql/employees/titles.ibd
                chown mysql:mysql /var/lib/mysql/employees/titles.ibd
                mysql -uroot -e "ALTER TABLE employees.titles IMPORT TABLESPACE;"' >/dev/null 2>&1
            ;;
        6)
            mysql_on node1 "CREATE INDEX idx_esr ON employees.titles (title, to_date, from_date);" >/dev/null \
                || { fail "CREATE INDEX on node1 failed"; result_summary+=("L${level}: FAIL (create index)"); failures=$((failures+1)); cleanup; return; }
            ;;
        7)
            docker exec "${PREFIX}node3" bash -c '
                ids=$(mysql -uroot -N -B -e "SELECT ID FROM information_schema.PROCESSLIST WHERE INFO LIKE \"SELECT SLEEP%\";")
                for id in $ids; do mysql -uroot -e "KILL ${id};"; done
                mysql -uroot -e "START REPLICA;"' >/dev/null 2>&1
            sleep 20  # let the relay log drain
            ;;
        8)
            docker exec "${PREFIX}node3" bash -c '
                sed -i "s/^server_id.*/server_id   = 3/" /etc/my.cnf.d/99-node.cnf
                sed -i "/^query_cache_size/d" /etc/my.cnf
                sed -i "/^innodb_data_file_path/d" /etc/my.cnf
                sed -i "s#^log-error.*#log-error                = /var/log/mysql/mysqld.log#" /etc/my.cnf
                systemctl start mysqld' >/dev/null 2>&1
            wait_for_mysqld node3 || true
            mysql_on node3 "START REPLICA;" >/dev/null 2>&1
            sleep 10
            ;;
        9)
            docker exec -i "${PREFIX}node1" tee /home/candidate/answer.sql >/dev/null <<'SQL'
-- Reading: everyone who has ever been assigned to d005 (the grader accepts
-- the current-assignment reading as well).
SELECT e.emp_no, e.first_name, e.last_name, e.birth_date, t.title
FROM employees e
JOIN dept_emp de ON de.emp_no = e.emp_no AND de.dept_no = 'd005'
JOIN titles   t  ON t.emp_no  = e.emp_no AND t.title LIKE '%Engineer%'
WHERE e.last_name = 'Trumbly'
ORDER BY e.birth_date;
SQL
            ;;
        11)
            docker exec -i "${PREFIX}node1" tee /home/candidate/report.md >/dev/null <<'MD'
# Findings
The buffer pool is 32M against a dataset of roughly 170M, so almost every
read goes to disk. max_connections is 40, which is low for an application
primary. innodb_io_capacity is 100, below even the default. table_open_cache
at 64 is far too small for this schema.

The slow log shows a query using OR across birth_date and last_name, which
cannot use an index in that form; rewriting it as a UNION of two indexed
lookups is the fix. There is also an IN (SELECT ...) that should be a join.

# Recommendations
Raise the buffer pool to a sensible fraction of RAM after checking what is
available, and raise io_capacity to match the storage. Add indexes on
last_name and birth_date. Any my.cnf change needs a restart, so it has to be
coordinated with the application owners rather than applied immediately.
Put monitoring in place (PMM) so this is visible before it becomes urgent.
MD
            ;;
        10)
            docker exec "${PREFIX}node1" bash -c '
                set -e
                systemctl stop mysqld
                xtrabackup --prepare --target-dir=/backups/full >/dev/null 2>&1
                rm -rf /var/lib/mysql/*
                xtrabackup --copy-back --target-dir=/backups/full >/dev/null 2>&1
                chown -R mysql:mysql /var/lib/mysql
                systemctl start mysqld' >/dev/null 2>&1
            wait_for_mysqld node1 || true
            ;;
    esac

    if run_check "$level"; then
        ok "fix worked, check.sh PASSED"
        result_summary+=("L${level}: ${GREEN}OK${RESET}")
    else
        fail "fix did not satisfy check.sh"
        result_summary+=("L${level}: ${RED}FAIL${RESET}")
        failures=$((failures+1))
    fi
    cleanup
}

# ============================================================================
# Negative cases: a wrong fix must NOT pass
# ============================================================================
# Every level above proves only that the known-good fix satisfies check.sh.
# Three false passes survived an audit because nothing ever proved that a
# wrong or incomplete fix is rejected. Each case below reproduces the end
# state such a fix leaves behind and asserts the grader refuses it. Reported
# as NEG lines in their own summary block. A NEG failure means the grader is
# too lenient, not that a question regressed.

neg_result() {  # neg_result <level> <what the wrong fix was> <check exit status>
    if [ "$3" -eq 0 ]; then
        fail "NEG L${1}: '${2}' was ACCEPTED by check.sh"
        result_summary+=("NEG L${1} (${2}): ${RED}WRONGLY ACCEPTED${RESET}")
        failures=$((failures+1))
    else
        ok "NEG L${1}: '${2}' correctly rejected"
        result_summary+=("NEG L${1} (${2}): ${GREEN}rejected${RESET}")
    fi
}

run_negative() {
    echo
    echo "==== Negative cases (a wrong fix must not pass) ===="

    # Q7: restarting mysqld on node3 kills the lock-holding session as a side
    # effect, the SQL thread comes back on its own, the relay log drains, and
    # the lag is gone with zero diagnosis — the exact skill the question tests.
    info "NEG L7: a wrong fix must be rejected"
    spawn 7 node1 node2 node3
    if wait_for_mysqld node1 && wait_for_topology; then
        sleep 20
        docker exec "${PREFIX}node3" systemctl restart mysqld >/dev/null 2>&1
        wait_for_mysqld node3 || true
        sleep 25  # the same drain time the real fix is given
        run_check 7; neg_result 7 "wrong fix" $?
    else
        fail "NEG L7: setup never came up"; result_summary+=("NEG L7: SETUP FAIL"); failures=$((failures+1))
    fi
    cleanup

    # Q10: a restore that brings back only employees.employees and stops. The
    # other five tables are still missing; a grader that counts one table
    # cannot tell. The state is produced the cheap way: full restore, then the
    # five tables a partial --export/IMPORT TABLESPACE route never brings back
    # are dropped.
    info "NEG L10: a wrong fix must be rejected"
    spawn 10 node1
    if wait_for_mysqld node1; then
        sleep 25
        docker exec "${PREFIX}node1" bash -c '
            set -e
            systemctl stop mysqld
            xtrabackup --prepare --target-dir=/backups/full >/dev/null 2>&1
            rm -rf /var/lib/mysql/*
            xtrabackup --copy-back --target-dir=/backups/full >/dev/null 2>&1
            chown -R mysql:mysql /var/lib/mysql
            systemctl start mysqld' >/dev/null 2>&1
        wait_for_mysqld node1 || true
        mysql_on node1 "DROP TABLE employees.departments, employees.dept_emp, employees.dept_manager, employees.salaries, employees.titles;" >/dev/null 2>&1
        run_check 10; neg_result 10 "wrong fix" $?
    else
        fail "NEG L10: mysqld never came up"; result_summary+=("NEG L10: SETUP FAIL"); failures=$((failures+1))
    fi
    cleanup

    # Q6: the trap the question is built around. (title, from_date, to_date)
    # serves the WHERE clause but puts the range column before the sort
    # column, so the rows still need a filesort. The grader's definition
    # backstop must not mistake it for the answer.
    info "NEG L6: a wrong fix must be rejected"
    spawn 6 node1
    if wait_for_setup node1 && wait_for_mysqld node1; then
        mysql_on node1 "CREATE INDEX idx_wrong ON employees.titles (title, from_date, to_date);" >/dev/null 2>&1
        run_check 6; neg_result 6 "wrong fix" $?
    else
        fail "NEG L6: setup never came up"; result_summary+=("NEG L6: SETUP FAIL"); failures=$((failures+1))
    fi
    cleanup

    # Q3: a replica that is connected (IO and SQL both Yes) but holds none of
    # the data. node1 loaded employees with binary logging off, so GTID
    # auto-positioning never back-fills it: this is exactly where a candidate
    # lands after reinstalling onto a wiped datadir. Produced the cheap way,
    # by dropping the database on node3 before wiring it up.
    info "NEG L3: a wrong fix must be rejected"
    spawn 3 node1 node2 node3
    if wait_for_mysqld node1 && wait_for_mysqld node2; then
        sleep 5
        docker exec "${PREFIX}node3" bash -c '
            dnf -y install percona-server-server percona-server-client >/dev/null 2>&1
            systemctl daemon-reload
            systemctl enable --now mysqld' >/dev/null 2>&1
        wait_for_mysqld node3 || true
        sleep 5
        mysql_on node3 "SET sql_log_bin=0; DROP DATABASE IF EXISTS employees;" >/dev/null 2>&1
        repoint node2 node1
        repoint node3 node1
        sleep 8
        run_check 3; neg_result 3 "wrong fix" $?
    else
        fail "NEG L3: setup never came up"; result_summary+=("NEG L3: SETUP FAIL"); failures=$((failures+1))
    fi
    cleanup
}

# ============================================================================
# Security guarantees
# ============================================================================
# Reported as SEC lines in their own summary block, so a failure here is never
# mistaken for a question regression. The first two probes run on the LIVE
# lab's exercise network (the one the controller puts candidates on), not on
# the smoketest network: isolation is a property of that network and can only
# be proven there. The probes carry the smoketest prefix and are removed at
# the end; nginx routes only to mysql-exercise-current-*, so they are
# invisible to a candidate.

sec_pass() { ok "SEC ${1}"; sec_summary+=("SEC ${1}: ${GREEN}OK${RESET}"); }
sec_fail() { fail "SEC ${1}: ${2}"; sec_summary+=("SEC ${1}: ${RED}FAIL${RESET} — ${2}"); failures=$((failures+1)); }
sec_skip() { info "SEC ${1}: skipped — ${2}"; sec_summary+=("SEC ${1}: ${YELLOW}SKIPPED${RESET} — ${2}"); }

lab_network() {
    # Whatever network the running controller spawns candidates on. Falls back
    # to the compose default so the check still runs when the controller is
    # down, and the caller fails loudly if the network does not exist at all.
    local n
    n=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTROLLER" 2>/dev/null \
        | sed -n 's/^INTERVIEW_NETWORK=//p' | head -1)
    echo "${n:-mysql_interview_net}"
}

# Drive the recorder the way ttyd does: load the unit's environment file,
# start one candidate-shell, type a marker, exit. $1 is an optional command
# prefix (the fallback probe uses `env -u HISTDIR`), $2 the marker. Bounded by
# `timeout` so a recorder that hangs fails the assertion instead of the suite.
drive_shell() {
    timeout 60 docker exec -i "${PREFIX}node1" bash -c \
        "set -a; . /etc/sysconfig/interview; set +a; $1 /usr/local/bin/candidate-shell" >/dev/null 2>&1 <<EOF
echo $2
exit
EOF
}

# Newest typescript for node1 under $1 that contains marker $2, or nothing.
transcript_with_marker() {
    docker exec "${PREFIX}node1" bash -c \
        "for f in \$(ls -t '$1'/node1-session-*.typescript 2>/dev/null); do
             grep -aq '$2' \"\$f\" && { echo \"\$f\"; exit 0; }
         done; exit 1" 2>/dev/null
}

run_security() {
    echo
    echo "==== Security guarantees ===="
    local net; net=$(lab_network)
    info "exercise network under test: $net"

    # ---- 1 + 2: no egress, no route to the controller -------------------------
    if ! docker network inspect "$net" >/dev/null 2>&1; then
        sec_fail "no internet egress" "network $net does not exist — is the lab running (./run.sh)?"
        sec_fail "controller unreachable" "network $net does not exist"
    else
        # Structural check first: the guarantee has to come from the network
        # being internal, not from the host happening to be offline today.
        local internal; internal=$(docker network inspect -f '{{.Internal}}' "$net" 2>/dev/null)
        docker rm -f "$PROBE" >/dev/null 2>&1 || true
        if ! docker run -d --rm --name "$PROBE" --network "$net" \
                --entrypoint /bin/sleep mysqlinterview/exercise-base 600 >/dev/null 2>&1; then
            sec_fail "no internet egress" "could not start a probe container on $net"
            sec_fail "controller unreachable" "could not start a probe container on $net"
        else
            if [ "$internal" != "true" ]; then
                sec_fail "no internet egress" "$net is not an internal network (docker network inspect -f '{{.Internal}}' = ${internal:-?})"
            elif docker exec "$PROBE" curl -sS -m5 -o /dev/null https://repo.percona.com/ >/dev/null 2>&1 \
                 || docker exec "$PROBE" curl -sS -m5 -o /dev/null http://1.1.1.1/ >/dev/null 2>&1; then
                sec_fail "no internet egress" "a node on $net reached the internet — the AI channel is open"
            else
                sec_pass "no internet egress"
            fi
            if docker exec "$PROBE" curl -sS -m3 -o /dev/null "http://${CONTROLLER}:5000/healthz" >/dev/null 2>&1; then
                sec_fail "controller unreachable" "http://${CONTROLLER}:5000/healthz answered from inside a node"
            else
                sec_pass "controller unreachable"
            fi
            docker rm -f "$PROBE" >/dev/null 2>&1 || true
        fi
    fi

    # ---- 3: the transcript recorder ------------------------------------------
    # Level 1 is the cheapest real node (one container, no data load). HISTDIR
    # is passed exactly as the controller passes it, so this covers the whole
    # chain: docker -e, interview-prep, /etc/sysconfig/interview, candidate-shell.
    info "transcript recorder (level 1, node1)"
    local run="smoketest-$(date +%s)"
    local histdir="/var/log/history/${run}/level-1"
    SPAWN_EXTRA=(-e "HISTDIR=${histdir}")
    spawn 1 node1
    local ready=0
    for _ in $(seq 1 60); do
        docker exec "${PREFIX}node1" test -s /etc/sysconfig/interview 2>/dev/null && { ready=1; break; }
        sleep 1
    done
    if [ "$ready" != 1 ]; then
        sec_fail "transcript written" "interview-prep never wrote /etc/sysconfig/interview"
        sec_fail "transcript fallback" "interview-prep never wrote /etc/sysconfig/interview"
    else
        if docker exec "${PREFIX}node1" grep -q "^HISTDIR=${histdir}\$" /etc/sysconfig/interview 2>/dev/null; then
            ok "HISTDIR reached /etc/sysconfig/interview (ttyd's environment file)"
        else
            fail "HISTDIR did not reach /etc/sysconfig/interview — ttyd would record to the fallback path"
        fi
        drive_shell ""            "SMOKETEST-MARKER-A"
        drive_shell ""            "SMOKETEST-MARKER-B"
        drive_shell "env -u HISTDIR" "SMOKETEST-MARKER-FALLBACK"

        local fa fb ff
        fa=$(transcript_with_marker "$histdir" SMOKETEST-MARKER-A)
        fb=$(transcript_with_marker "$histdir" SMOKETEST-MARKER-B)
        if [ -z "$fa" ] || [ -z "$fb" ]; then
            sec_fail "transcript written" "no ${histdir}/node1-session-<pid>.typescript holds what was typed"
        elif [ "$fa" = "$fb" ]; then
            sec_fail "transcript written" "two shells recorded into the same file (${fa##*/}); sessions would interleave"
        else
            sec_pass "transcript written (${fa##*/}, ${fb##*/})"
        fi
        ff=$(transcript_with_marker /var/log/history/level-1 SMOKETEST-MARKER-FALLBACK)
        if [ -n "$ff" ]; then
            sec_pass "transcript fallback without HISTDIR (level-1/${ff##*/})"
        else
            sec_fail "transcript fallback" "no /var/log/history/level-1/node1-session-<pid>.typescript holds what was typed"
        fi
    fi
    cleanup

    # ---- 4: terminal-guard.js is injected by nginx ---------------------------
    # A real request through nginx to a real ttyd, because the injection is a
    # sub_filter on the proxied HTML and only a proxied page proves it. The
    # ttyd here runs straight from the base image with no systemd, since the
    # thing under test is nginx, not the container boot.
    info "terminal-guard injection through nginx"
    if [ "$(docker inspect -f '{{.State.Running}}' "$NGINX" 2>/dev/null)" != "true" ]; then
        sec_fail "terminal-guard injected" "$NGINX is not running"
    elif [ -z "${LAB_PASS:-}" ]; then
        sec_skip "terminal-guard injected" "LAB_PASS (candidate password) not set, cannot fetch /term/ through basic auth"
    else
        local port
        port=$(docker port "$NGINX" 80/tcp 2>/dev/null | head -1 | sed 's/.*://')
        [ -n "$port" ] || port=$(sed -n 's/^HOST_PORT=//p' .env 2>/dev/null)
        port="${port:-8081}"
        docker rm -f "$GUARD_CONTAINER" >/dev/null 2>&1 || true
        if ! docker run -d --rm --name "$GUARD_CONTAINER" --hostname "$GUARD_NODE" --network "$net" \
                --entrypoint /usr/local/bin/ttyd mysqlinterview/exercise-base \
                -p 7681 -i 0.0.0.0 -b "/term/${GUARD_NODE}/" /bin/bash >/dev/null 2>&1; then
            sec_fail "terminal-guard injected" "could not start ${GUARD_CONTAINER} on $net"
        else
            sleep 3
            local body code
            body=$(curl -s -m10 -u "${LAB_USER:-candidate}:${LAB_PASS}" -w '\n%{http_code}' \
                        "http://127.0.0.1:${port}/term/${GUARD_NODE}/" 2>/dev/null)
            code=${body##*$'\n'}
            if [ "$code" != "200" ]; then
                sec_fail "terminal-guard injected" "GET /term/${GUARD_NODE}/ returned HTTP ${code:-none} (401 means LAB_USER/LAB_PASS is wrong)"
            elif grep -q 'Starting exercise' <<<"$body"; then
                sec_fail "terminal-guard injected" "nginx served its 'Starting exercise' page: it could not reach ${GUARD_CONTAINER} on $net"
            elif grep -q 'src="/static/terminal-guard.js"' <<<"$body" &&
                 grep -q 'src="/static/cadence.js"' <<<"$body"; then
                sec_pass "terminal-guard injected"
            else
                sec_fail "terminal-guard injected" "ttyd page came back without the cadence.js and terminal-guard.js script tags"
            fi
            docker rm -f "$GUARD_CONTAINER" >/dev/null 2>&1 || true
        fi
    fi
}

# ---- arguments ----
levels=()
do_security=0
do_negative=0
for a in "$@"; do
    case "$a" in
        security|sec) do_security=1 ;;
        negative|neg) do_negative=1 ;;
        ''|*[!0-9]*)  echo "smoketest.sh: unknown argument '$a' (levels are numbers; 'negative' and 'security' run those sections)" >&2; exit 2 ;;
        *)            levels+=("$a") ;;
    esac
done
if [ "$#" -eq 0 ]; then
    levels=(1 2 3 4 5 6 7 8 9 10 11)
    do_security=1
    do_negative=1
fi

# The paste-guard assertion needs the candidate credential. Ask on a terminal
# when one is there; never from stdin, which may be carrying this very script.
if [ "$do_security" = 1 ] && [ -z "${LAB_PASS:-}" ] && { : </dev/tty; } 2>/dev/null; then
    read -rsp "candidate password for the paste-guard check (Enter to skip it): " LAB_PASS </dev/tty; echo
fi

ensure_net

# Progress lines name the question by its candidate-facing title, never by its
# fix: the run log lands on the operator's laptop and gets pasted around.
title_of() {
    sed -n '1{s/^# *//;p;}' "$(level_dir "$1")/README.md" 2>/dev/null
}

for lvl in ${levels[@]+"${levels[@]}"}; do
    run_level "$lvl" "$(title_of "$lvl")"
done

if [ "${#levels[@]}" -gt 0 ]; then
    echo
    echo "==== Artifacts preserved by check.sh ===="
    for f in level-9/answer.sql level-11/report.md; do
        # Only meaningful for levels that ran in this invocation.
        lvl_of="${f%%/*}"; lvl_of="${lvl_of#level-}"
        case " ${levels[*]} " in *" ${lvl_of} "*) ;; *) continue ;; esac
        sz=$(docker run --rm --entrypoint sh -v "$HISTVOL":/h mysqlinterview/exercise-base -c "wc -c < /h/$f 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$sz" ] && [ "$sz" -gt 0 ] 2>/dev/null; then
            printf "  ${GREEN}\xe2\x9c\x93 %s (%s bytes)${RESET}\n" "$f" "$sz"
        else
            printf "  ${RED}\xe2\x9c\x97 %s missing${RESET}\n" "$f"
            failures=$((failures+1))
        fi
    done
fi

[ "$do_negative" = 1 ] && run_negative
[ "$do_security" = 1 ] && run_security

echo
echo "==== Summary ===="
for line in ${result_summary[@]+"${result_summary[@]}"}; do
    printf "  %b\n" "$line"
done
if [ "${#sec_summary[@]}" -gt 0 ]; then
    echo "  ---- security guarantees ----"
    for line in "${sec_summary[@]}"; do
        printf "  %b\n" "$line"
    done
fi

if [ "$failures" -gt 0 ]; then
    printf "\n${RED}%d failure(s)${RESET}\n" "$failures"
    exit 1
fi
exit 0
