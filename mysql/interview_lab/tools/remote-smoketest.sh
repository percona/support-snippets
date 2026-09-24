#!/usr/bin/env bash
# Run smoketest.sh against the lab server WITHOUT copying it there.
#
#   ./tools/remote-smoketest.sh user@host [-i key] [-p port] [-d remote_dir] [levels|negative|security ...]
#
#   ./tools/remote-smoketest.sh ec2-user@1.2.3.4 -i ~/.ssh/lab.pem            # all 11 + negative + security
#   ./tools/remote-smoketest.sh ec2-user@1.2.3.4 -i ~/.ssh/lab.pem 3 8        # two levels
#   ./tools/remote-smoketest.sh ec2-user@1.2.3.4 -i ~/.ssh/lab.pem negative   # wrong fixes must fail
#   ./tools/remote-smoketest.sh ec2-user@1.2.3.4 -i ~/.ssh/lab.pem security   # guarantees only
#
# smoketest.sh is the answer key: its per-level fix blocks are the exact
# solution to every question. deploy.sh therefore does not rsync it to the
# server, because a candidate is root in a privileged container and can mount
# the host's disk. The suite still has to run where the images and the Docker
# daemon are, so this streams the script over ssh and has the remote bash read
# it from a file descriptor: it never lands on the server's disk and never
# appears on a command line. The remote cwd is the deployed lab directory,
# which is all smoketest.sh needs; exercises/*/check.sh is there because the
# controller needs it.
#
# The candidate password, when available, travels first on the same stream
# and is read off before the script starts, so it is not on a command line
# either. Without it the paste-guard assertion is reported as SKIPPED.
#   LAB_PASS   candidate password (prompted if unset and a terminal is present)
#   LAB_USER   defaults to "candidate"
set -euo pipefail
# Resolved before the cd below, which would break a relative $0 for --help.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."

REMOTE_DIR="mysql-interview-lab"
SSH_PORT=22
SSH_KEY=""
TARGET=""
ARGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -i) SSH_KEY="$2"; shift 2 ;;
        -p) SSH_PORT="$2"; shift 2 ;;
        -d) REMOTE_DIR="$2"; shift 2 ;;
        # The whole header comment, however long it grows.
        -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$SELF"; exit 0 ;;
        *)
            if [ -z "$TARGET" ]; then TARGET="$1"
            else ARGS+=("$1"); fi
            shift ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "usage: ./tools/remote-smoketest.sh user@host [-i keyfile] [-p port] [-d remote_dir] [levels|negative|security ...]" >&2
    exit 1
fi
[ -f smoketest.sh ] || { echo "smoketest.sh not found next to this tool" >&2; exit 1; }

# Only what smoketest.sh itself accepts — numbers, "negative"/"neg" and
# "security"/"sec" — and validating it here means nothing needs quoting on
# the remote side.
remote_args=""
for a in ${ARGS[@]+"${ARGS[@]}"}; do
    case "$a" in
        security|sec) remote_args+=" $a" ;;
        negative|neg) remote_args+=" $a" ;;
        ''|*[!0-9]*)  echo "unknown argument '$a': levels are numbers, 'negative' runs the wrong-fix cases, 'security' the guarantees" >&2; exit 1 ;;
        *)            remote_args+=" $a" ;;
    esac
done

# Quiet OpenSSH 10's post-quantum warning; older clients ignore the option.
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new
          -o IgnoreUnknown=WarnWeakCrypto -o WarnWeakCrypto=no-pq-kex)
[ -n "$SSH_KEY" ] && SSH_OPTS+=(-i "$SSH_KEY")

if [ -z "${LAB_PASS:-}" ] && { : </dev/tty; } 2>/dev/null; then
    read -rsp "candidate password for the paste-guard check (Enter to skip it): " LAB_PASS </dev/tty; echo
fi
LAB_USER="${LAB_USER:-candidate}"

# Remote side, in order: fd 3 takes over the incoming stream and stdin becomes
# /dev/null, so nothing the suite runs can swallow the script; the first line
# is the password; then bash reads the rest straight from fd 3. bash marks the
# script descriptor close-on-exec, so no child process can see it either.
# smoketest.sh recognises a /dev/fd $0 and stays in the cwd.
# Before starting, any suite left orphaned by an earlier dropped session is
# killed: it keeps running after ssh dies and would collide with this run on
# the same container names. The pattern is anchored so it matches only a
# suite already exec'd into `bash /dev/fd/3`, not this shell, whose own
# command line contains that string.
REMOTE_CMD="cd '$REMOTE_DIR' || exit 2
docker info >/dev/null 2>&1 || { echo 'docker is not usable as $(whoami) on the server (log out and in after bootstrap, or: sudo usermod -aG docker \$USER)' >&2; exit 3; }
pkill -f '^bash /dev/fd/3' 2>/dev/null; docker rm -f \$(docker ps -aq --filter name=smoketest-) >/dev/null 2>&1; true
{ IFS= read -r LAB_PASS <&3 && export LAB_PASS LAB_USER='$LAB_USER' && exec bash /dev/fd/3${remote_args}; } 3<&0 </dev/null"

echo "==> streaming smoketest.sh to $TARGET:$REMOTE_DIR (it is not written to disk there)"
{ printf '%s\n' "${LAB_PASS:-}"; cat smoketest.sh; } | ssh "${SSH_OPTS[@]}" "$TARGET" "$REMOTE_CMD"
