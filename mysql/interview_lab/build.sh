#!/usr/bin/env bash
# Build the base image and every per-level image that has a Dockerfile.
set -euo pipefail
cd "$(dirname "$0")"

# The employees dataset is fetched, not committed. The base image bakes it
# into its datadir at build time so container boot is instant; question 2
# needs its own copy because the candidate has to load it by hand.
if [[ ! -s exercises/_base/employees-db.tar.gz ]]; then
    ./tools/fetch-employees.sh
fi
cp -f exercises/_base/employees-db.tar.gz exercises/02-import-company/employees-db.tar.gz

# Each image's output goes to a scratch file and is shown only if the build
# fails: streamed, dnf and BuildKit progress were three quarters of every
# deploy log. VERBOSE=1 streams it as before.
build() {  # build <tag> <dir>
    local tag=$1 dir=$2 out t0=$SECONDS
    if [[ "${VERBOSE:-0}" = 1 ]]; then docker build -t "$tag" "$dir"; return; fi
    out=$(mktemp)
    if docker build --progress=plain -t "$tag" "$dir" >"$out" 2>&1; then
        echo "    built in $((SECONDS - t0))s"
        rm -f "$out"
    else
        echo "==> building ${tag} FAILED; the last 60 lines of its output:"
        tail -n 60 "$out"
        rm -f "$out"
        return 1
    fi
}

echo "==> building mysqlinterview/exercise-base"
build mysqlinterview/exercise-base exercises/_base

for d in exercises/[0-9][0-9]-*/ ; do
    level=$(basename "$d" | cut -c1-2)
    if [[ -f "$d/Dockerfile" ]]; then
        tag="mysqlinterview/exercise-${level}"
        echo "==> building ${tag} (from ${d})"
        build "${tag}" "${d}"
    else
        echo "    (skipping ${d}, no Dockerfile yet)"
    fi
done

echo "==> done"
