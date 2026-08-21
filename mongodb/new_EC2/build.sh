#!/usr/bin/env bash
# Build the base image and every per-level image that has a Dockerfile.
set -euo pipefail
cd "$(dirname "$0")"

# The percona.company fixture is generated, not committed (5.6 MB of identical
# binary across three questions). Regenerate it when a fresh clone lacks it.
# gen-company.py is deterministic, so every build ships the same 100k documents.
FIXTURES=(exercises/02-import-company/company.json.tar.gz
          exercises/06-missing-index/company.json.tar.gz
          exercises/10-restore-backup/company.json.tar.gz)
missing=0
for f in "${FIXTURES[@]}"; do
    [[ -s "$f" ]] || missing=1
done
if [[ "$missing" = 1 ]]; then
    command -v python3 >/dev/null 2>&1 || {
        echo "error: python3 is needed to generate the percona.company fixture." >&2
        exit 1
    }
    echo "==> generating the percona.company fixture (tools/gen-company.py)"
    python3 tools/gen-company.py
fi

echo "==> building interview/exercise-base"
docker build -t interview/exercise-base exercises/_base

for d in exercises/[0-9][0-9]-*/ ; do
    level=$(basename "$d" | cut -c1-2)
    if [[ -f "$d/Dockerfile" ]]; then
        tag="interview/exercise-${level}"
        echo "==> building ${tag} (from ${d})"
        docker build -t "${tag}" "${d}"
    else
        echo "    (skipping ${d}, no Dockerfile yet)"
    fi
done

echo "==> done"
