#!/usr/bin/env bash
# Drive headless Chromium through the candidate flow of a deployed lab.
#
#   ./tools/browser-test.sh user@host [-i key] [-p port]
#
#   CAND_PASS / INTV_PASS   the two basic-auth passwords (prompted if unset)
#   DRY=1                   only the read-only case: 401 without credentials and
#                           the page with them. Touches nothing, resets nothing.
#   FORCE=1                 run even though an exam is in progress: the lab is
#                           reset first. Never during an interview.
#
# smoketest.sh proves every grader; this proves the page a candidate uses. It
# starts the exam, checks the watermark and the copy block, waits for the
# terminal's shell prompt over its websocket, presses Send with the Q1 fix
# applied and watches the page land on question 2, then sends a stale Send from
# a second tab and expects the 409 reload. Any page error or console error on
# the candidate page fails it. It ends with the interviewer's POST /reset, so
# the lab is back at the briefing whatever happened.
#
# ssh is used for one thing: applying the Q1 fix inside the node1 container,
# with the commands on stdin, as remote-smoketest.sh streams the suite. That fix
# is answer-key material, which is why deploy.sh never ships this directory.
# Everything else goes over HTTP to http://host/ like a candidate's browser.
#
# Needs node (22+) and, once, npm access to install the pinned Playwright into
# tools/browser-test/node_modules. The pin matches the Chromium already cached
# in ~/Library/Caches/ms-playwright, so no browser is downloaded.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."

SSH_PORT=22
SSH_KEY=""
TARGET=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -i) SSH_KEY="$2"; shift 2 ;;
        -p) SSH_PORT="$2"; shift 2 ;;
        # The whole header comment, however long it grows.
        -h|--help) awk 'NR > 1 && !/^#/ {exit} NR > 1' "$SELF"; exit 0 ;;
        *)
            if [ -z "$TARGET" ]; then TARGET="$1"; shift
            else echo "unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "usage: ./tools/browser-test.sh user@host [-i keyfile] [-p port]" >&2
    exit 1
fi
command -v node >/dev/null 2>&1 || { echo "error: node is required (brew install node)" >&2; exit 1; }

# Same idiom as launch-lab.sh: -r /dev/tty is true on macOS even without a
# controlling terminal, so opening it is the only reliable test.
for v in CAND_PASS INTV_PASS; do
    eval "cur=\${$v:-}"
    if [ -z "$cur" ]; then
        if ! { : </dev/tty; } 2>/dev/null; then
            echo "error: $v is not set and there is no terminal to ask on." >&2
            echo "  run with: CAND_PASS=... INTV_PASS=... $0 $TARGET" >&2
            exit 1
        fi
        case "$v" in
            CAND_PASS) read -rsp "candidate password   : " cur </dev/tty ;;
            INTV_PASS) read -rsp "interviewer password : " cur </dev/tty ;;
        esac
        echo
        [ -n "$cur" ] || { echo "error: $v must not be empty." >&2; exit 1; }
        eval "$v=\$cur"
    fi
done
export CAND_PASS INTV_PASS

DIR=tools/browser-test
# Install once, from the lockfile, and again only when the lockfile moved.
# PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD is belt and braces: the pinned playwright
# expects the Chromium build already in the cache, and a laptop without it
# gets told what to run by the script rather than a silent 150 MB download.
if [ ! -d "$DIR/node_modules/playwright" ] || [ "$DIR/package-lock.json" -nt "$DIR/node_modules/.package-lock.json" ]; then
    echo "==> installing the pinned Playwright into $DIR/node_modules"
    (cd "$DIR" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --no-audit --no-fund --loglevel=error)
fi

MODE="full run"; [ "${DRY:-}" = 1 ] && MODE="dry mode"
echo "==> browser test against http://${TARGET#*@}/ ($MODE)"
LAB_HOST="${TARGET#*@}" SSH_TARGET="$TARGET" SSH_KEY="$SSH_KEY" SSH_PORT="$SSH_PORT" \
    exec node "$DIR/browser-test.js"
