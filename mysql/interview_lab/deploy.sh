#!/usr/bin/env bash
# One-command deploy from your laptop to a remote server over SSH.
#
#   ./deploy.sh user@host [-i key] [-p port] [-d remote_dir] [-P] [-K] [--keep-auth]
#
# Auth modes:
#   (default)  key-based SSH + passwordless sudo  (the EC2 default)
#   -P         password SSH auth (requires `sshpass` on your laptop); you are
#              prompted once for the login password. sudo reuses it by default.
#   -K         prompt for a separate sudo password (use if sudo differs, or with
#              a key-auth box whose sudo still needs a password).
#   --keep-auth  keep both existing basic-auth hashes on a redeploy.
#
# What it does, over SSH:
#   1. rsync this project to the server (excludes state, secrets, caches, and
#      the answer key: SOLUTIONS.md and smoketest.sh never reach the box)
#   2. run deploy/bootstrap.sh   -> installs Docker + Compose (auto-detect distro)
#   3. run gen-auth.sh           -> writes basic-auth files, unless --keep-auth
#   4. set HOST_PORT=80, then ./build.sh && ./run.sh
#
# Re-run any time to push changes and rebuild. Idempotent.
#
# Verify afterwards with ./tools/remote-smoketest.sh, which streams the suite
# over ssh for the run instead of leaving it on the server's disk.
set -euo pipefail
cd "$(dirname "$0")"

REMOTE_DIR="mysql-interview-lab"
SSH_PORT=22
SSH_KEY=""
TARGET=""
PASSWORD_AUTH=0
ASK_SUDO=0
KEEP_AUTH=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -i) SSH_KEY="$2"; shift 2 ;;
        -p) SSH_PORT="$2"; shift 2 ;;
        -d) REMOTE_DIR="$2"; shift 2 ;;
        -P) PASSWORD_AUTH=1; shift ;;
        -K|--sudo-pass) ASK_SUDO=1; shift ;;
        --keep-auth) KEEP_AUTH=1; shift ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *)
            if [ -z "$TARGET" ]; then TARGET="$1"; shift
            else echo "unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "usage: ./deploy.sh user@host [-i keyfile] [-p port] [-d remote_dir] [-P] [-K] [--keep-auth]" >&2
    exit 1
fi

REMOTE_USER="${TARGET%@*}"
# OpenSSH 10 prints a three-line post-quantum warning on every connection to
# AL2023's sshd; a deploy makes a dozen. IgnoreUnknown keeps older clients,
# which do not know the option, from refusing it.
QUIET_PQ="-o IgnoreUnknown=WarnWeakCrypto -o WarnWeakCrypto=no-pq-kex"
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new $QUIET_PQ)
[ -n "$SSH_KEY" ] && SSH_OPTS+=(-i "$SSH_KEY")
RSYNC_SSH="ssh -p $SSH_PORT -o StrictHostKeyChecking=accept-new $QUIET_PQ"
[ -n "$SSH_KEY" ] && RSYNC_SSH="$RSYNC_SSH -i $SSH_KEY"

# ---- auth setup ----
SUDO_PASS=""
if [ "$PASSWORD_AUTH" = 1 ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "error: -P needs 'sshpass' on this machine." >&2
        echo "  install it:  apt install sshpass | dnf install sshpass | brew install sshpass" >&2
        echo "  (or skip -P and use a key:  ssh-copy-id user@host  then  ./deploy.sh user@host -i key)" >&2
        exit 1
    fi
    read -rsp "SSH password for $TARGET: " SSH_PASS; echo
    export SSHPASS="$SSH_PASS"
    SUDO_PASS="$SSH_PASS"   # most password boxes use the same password for sudo
fi
if [ "$ASK_SUDO" = 1 ]; then
    sp=""
    [ "$PASSWORD_AUTH" = 1 ] && sp=" [Enter = same as SSH login]"
    read -rsp "sudo password${sp}: " ans; echo
    [ -n "$ans" ] && SUDO_PASS="$ans"
fi

# Wrap ssh/rsync with sshpass only in password mode (avoids empty-array issues
# on older bash). run_ssh runs a remote command; run_rsync wraps rsync.
if [ "$PASSWORD_AUTH" = 1 ]; then
    run_ssh()   { sshpass -e ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }
    run_rsync() { sshpass -e rsync "$@"; }
else
    run_ssh()   { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }
    run_rsync() { rsync "$@"; }
fi

# Run a remote command under sudo, feeding the sudo password on stdin via -S.
# Harmless when sudo is passwordless (empty password is ignored).
sudo_run() {
    printf '%s\n' "$SUDO_PASS" | run_ssh "cd '$REMOTE_DIR' && sudo -S -p '' bash -c $1"
}

echo "==> [1/5] checking SSH to $TARGET"
run_ssh 'echo connected as $(whoami) on $(. /etc/os-release; echo "$PRETTY_NAME")'

# Without the questions the lab would build, run and serve nothing at all.
if ! ls -d exercises/[0-9][0-9]-*/ >/dev/null 2>&1; then
    echo "error: no questions under exercises/; refusing to deploy an empty exam." >&2
    exit 1
fi

echo "==> [2/5] syncing project to $TARGET:$REMOTE_DIR"
run_ssh "mkdir -p '$REMOTE_DIR'"
run_rsync -az --delete -e "$RSYNC_SSH" \
    --exclude '.git' \
    --exclude '.claude' \
    --exclude 'SOLUTIONS.md' \
    --exclude 'smoketest.sh' \
    `# The candidate is root in a privileged container and can reach the host` \
    `# filesystem, so nothing that helps them belongs on the box. The questions` \
    `# are the obvious one — candidate-exercises.txt is all eleven, and reading` \
    `# ahead is a real advantage. The operator docs carry the AWS account id and` \
    `# the debrief script. exercises/*/README.md is NOT excluded: the controller` \
    `# renders the current question from it.` \
    --exclude '/candidate-exercises.txt' \
    --exclude '/RUNBOOK.md' \
    --exclude '/README.md' \
    --exclude 'deploy/*.md' \
    --exclude '/launch-lab.sh' \
    --exclude 'tools/allow-ip.sh' \
    --exclude 'tools/destroy-lab.sh' \
    --exclude 'tools/remote-smoketest.sh' \
    `# The browser test applies the Q1 fix: answer-key material, like smoketest.sh.` \
    --exclude 'tools/browser-test.sh' \
    --exclude 'tools/browser-test' \
    `# build.sh copies _base's dataset into question 2 on the server; sending` \
    `# Q2's own copy as well was 36 MB of upload for nothing.` \
    --exclude '/exercises/[0-9]*/employees-db.tar.gz' \
    --exclude 'state/' \
    --exclude '.env' \
    --exclude 'nginx/auth/htpasswd' \
    --exclude 'nginx/auth/htpasswd-interviewer' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '.env.local' \
    --exclude '*.pem' \
    --exclude '*.key' \
    ./ "$TARGET:$REMOTE_DIR/"

# rsync --delete never removes a file that matches an exclude: that protection is
# what keeps .env and state/ alive on the server. The price is that anything
# excluded AFTER it was once shipped stays there forever. Delete the answer key,
# the questions and the operator docs explicitly, so a box first deployed before
# they were excluded does not keep them where a privileged candidate can read them.
run_ssh "cd '$REMOTE_DIR' && rm -f SOLUTIONS.md smoketest.sh candidate-exercises.txt \
    RUNBOOK.md README.md launch-lab.sh DEMO.md DEPLOYMENT.md deploy/*.md \
    tools/allow-ip.sh tools/destroy-lab.sh tools/remote-smoketest.sh tools/browser-test.sh \
    && rm -rf .claude tools/browser-test"

echo "==> [3/5] installing Docker on the server (auto-detect distro)"
# bootstrap.sh grants docker access to $SUDO_USER, which sudo sets to $REMOTE_USER.
run_ssh "cd '$REMOTE_DIR' && chmod +x deploy/bootstrap.sh"
sudo_run "'bash deploy/bootstrap.sh'"

echo "==> [4/5] generating basic-auth credentials"
if [ "$KEEP_AUTH" = 1 ]; then
    sudo_run "'test -s nginx/auth/htpasswd && test -s nginx/auth/htpasswd-interviewer'" \
        || { echo "error: --keep-auth requires both existing auth files" >&2; exit 1; }
    echo "    keeping existing auth hashes"
else
    # Passwords may be supplied via CAND_PASS / INTV_PASS env vars; otherwise prompt.
    [ -n "${CAND_PASS:-}" ] || { read -rsp "  candidate password   : " CAND_PASS; echo; }
    [ -n "${INTV_PASS:-}" ] || { read -rsp "  interviewer password : " INTV_PASS; echo; }
    printf '%s\n%s\n' "$CAND_PASS" "$INTV_PASS" \
        | run_ssh "cd '$REMOTE_DIR' && chmod +x gen-auth.sh && ./gen-auth.sh"
fi

echo "==> [5/5] building + starting the lab on :80"
# .env is excluded from the rsync, so it persists on the server and is edited
# in place rather than overwritten: besides HOST_PORT it carries
# CONTROLLER_SECRET, the value nginx stamps on every request it forwards and
# the controller demands. Without it compose falls back to a fixed default on
# both sides, which works but is a shared, published value. Generated once,
# on the box, from /dev/urandom; re-deploys keep it.
run_ssh "cd '$REMOTE_DIR' && bash -s" <<'REMOTE'
touch .env
grep -q '^CONTROLLER_SECRET=' .env \
    || printf 'CONTROLLER_SECRET=%s\n' "$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" >> .env
grep -v '^HOST_PORT=' .env > .env.tmp || true
echo 'HOST_PORT=80' >> .env.tmp
mv .env.tmp .env
chmod +x build.sh run.sh
REMOTE
# stderr merged on the box: ssh carries the two streams separately, and the
# build's "done" used to arrive before the last image's own output.
sudo_run "'(./build.sh && ./run.sh) 2>&1'"

HOST_ONLY="${TARGET#*@}"
cat <<EOF

==> done.
    Candidate URL    : http://${HOST_ONLY}/            (login: candidate)
    Interviewer view : http://${HOST_ONLY}/interviewer/ (login: interviewer)
    Reset progress   : curl -u interviewer:<pass> -X POST http://${HOST_ONLY}/reset
    Verify (11/11 + SEC all OK, ~15-20 min):
        ./tools/remote-smoketest.sh ${TARGET}${SSH_KEY:+ -i $SSH_KEY}${SSH_PORT:+ -p $SSH_PORT}

    Make sure the security group allows inbound TCP 80 from your colleagues.
EOF
