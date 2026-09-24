#!/usr/bin/env bash
# Tear everything down: controller, nginx, and any live exercise container.
set -euo pipefail
cd "$(dirname "$0")"

# Remove any live exercise containers. Levels spawn per-node names like
# exercise-current-node1 / exercise-prewarm-node2, so match by prefix
# (plus the legacy bare "mysql-exercise-current" name).
ids="$(docker ps -aq --filter 'name=^/mysql-exercise-current' --filter 'name=^/mysql-exercise-prewarm')"
[ -n "$ids" ] && docker rm -f $ids 2>/dev/null || true
docker compose down
echo "stopped"
