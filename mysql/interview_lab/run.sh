#!/usr/bin/env bash
# Bring the controller + nginx up. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

if ! docker image inspect mysqlinterview/exercise-base >/dev/null 2>&1; then
    echo "mysqlinterview/exercise-base is not built. Running build.sh first..."
    ./build.sh
fi

# nginx now requires the basic-auth files; without them every request 500s.
if [ ! -s nginx/auth/htpasswd ] || [ ! -s nginx/auth/htpasswd-interviewer ]; then
    echo "Missing basic-auth files. Generate them first:" >&2
    echo "    ./gen-auth.sh" >&2
    exit 1
fi

# The exercise network must exist before compose starts (nginx joins it), and
# it must be INTERNAL from the first moment: no gateway, so a candidate's root
# shell has no route to the internet. The controller would repair a plain
# bridge by tearing it down and recreating it, restarting nginx to rebind its
# published port, but there is no reason to make it. nginx keeps its port
# through the separate, non-internal controller network compose creates.
docker network inspect mysql_interview_net >/dev/null 2>&1 \
    || docker network create --internal mysql_interview_net

docker compose up -d --build
echo
# .env is where the port lives; compose defaults to 8081 when it is absent.
port=$(sed -n 's/^HOST_PORT=//p' .env 2>/dev/null | tail -1)
echo "Open: http://localhost:${port:-8081}"
