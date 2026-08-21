#!/usr/bin/env bash
# Bring the controller + nginx up. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

if ! docker image inspect interview/exercise-base >/dev/null 2>&1; then
    echo "interview/exercise-base is not built. Running build.sh first..."
    ./build.sh
fi

# nginx now requires the basic-auth files; without them every request 500s.
if [ ! -s nginx/auth/htpasswd ] || [ ! -s nginx/auth/htpasswd-interviewer ]; then
    echo "Missing basic-auth files. Generate them first:" >&2
    echo "    ./gen-auth.sh" >&2
    exit 1
fi

# Ensure the shared network exists before compose starts.
docker network inspect interview_net >/dev/null 2>&1 || docker network create interview_net

docker compose up -d --build
echo
echo "Open: http://localhost:${HOST_PORT:-8080}"
