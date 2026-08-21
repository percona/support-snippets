#!/usr/bin/env bash
# One-command deploy from your laptop to a remote server over SSH.
#
#   ./deploy.sh user@host [-i key] [-p port] [-d remote_dir] [-P] [-K]
#
# Auth modes:
#   (default)  key-based SSH + passwordless sudo  (the EC2 default)
#   -P         password SSH auth (requires `sshpass` on your laptop); you are
#              prompted once for the login password. sudo reuses it by default.
#   -K         prompt for a separate sudo password (use if sudo differs, or with
#              a key-auth box whose sudo still needs a password).
#
# What it does, over SSH:
#   1. rsync this project to the server (excludes state, secrets, caches)
#   2. run deploy/bootstrap.sh   -> installs Docker + Compose (auto-detect distro)
#   3. run gen-auth.sh           -> writes the basic-auth files (passwords prompted here)
#   4. set HOST_PORT=80, then ./build.sh && ./run.sh
#
# Re-run any time to push changes and rebuild. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"

REMOTE_DIR="dba-interview-lab"
SSH_PORT=22
SSH_KEY=""
TARGET=""
PASSWORD_AUTH=0
ASK_SUDO=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -i) SSH_KEY="$2"; shift 2 ;;
        -p) SSH_PORT="$2"; shift 2 ;;
        -d) REMOTE_DIR="$2"; shift 2 ;;
        -P) PASSWORD_AUTH=1; shift ;;
        -K|--sudo-pass) ASK_SUDO=1; shift ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *)
            if [ -z "$TARGET" ]; then TARGET="$1"; shift
            else echo "unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "usage: ./deploy.sh user@host [-i keyfile] [-p port] [-d remote_dir] [-P] [-K]" >&2
    exit 1
fi

REMOTE_USER="${TARGET%@*}"
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
[ -n "$SSH_KEY" ] && SSH_OPTS+=(-i "$SSH_KEY")
RSYNC_SSH="ssh -p $SSH_PORT -o StrictHostKeyChecking=accept-new"
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

echo "==> [2/5] syncing project to $TARGET:$REMOTE_DIR"
run_ssh "mkdir -p '$REMOTE_DIR'"
run_rsync -az --delete -e "$RSYNC_SSH" \
    --exclude '.git' \
    --exclude 'state/' \
    --exclude 'nginx/auth/htpasswd' \
    --exclude 'nginx/auth/htpasswd-interviewer' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '.env.local' \
    --exclude '*.pem' \
    --exclude '*.key' \
    ./ "$TARGET:$REMOTE_DIR/"

echo "==> [3/5] installing Docker on the server (auto-detect distro)"
# bootstrap.sh grants docker access to $SUDO_USER, which sudo sets to $REMOTE_USER.
run_ssh "cd '$REMOTE_DIR' && chmod +x deploy/bootstrap.sh"
sudo_run "'bash deploy/bootstrap.sh'"

echo "==> [4/5] generating basic-auth credentials"
# Passwords may be supplied via CAND_PASS / INTV_PASS env vars (handy for
# scripted/non-interactive deploys); otherwise prompt for them here.
[ -n "${CAND_PASS:-}" ] || { read -rsp "  candidate password   : " CAND_PASS; echo; }
[ -n "${INTV_PASS:-}" ] || { read -rsp "  interviewer password : " INTV_PASS; echo; }
printf '%s\n%s\n' "$CAND_PASS" "$INTV_PASS" \
    | run_ssh "cd '$REMOTE_DIR' && chmod +x gen-auth.sh && ./gen-auth.sh"

echo "==> [5/5] building + starting the lab on :80"
run_ssh "cd '$REMOTE_DIR' && echo 'HOST_PORT=80' > .env && chmod +x build.sh run.sh"
sudo_run "'./build.sh && ./run.sh'"

HOST_ONLY="${TARGET#*@}"
cat <<EOF

==> done.
    Candidate URL    : http://${HOST_ONLY}/            (login: candidate)
    Interviewer view : http://${HOST_ONLY}/interviewer/ (login: interviewer)
    Reset progress   : curl -u interviewer:<pass> -X POST http://${HOST_ONLY}/reset

    Make sure the security group allows inbound TCP 80 from your colleagues.
EOF
