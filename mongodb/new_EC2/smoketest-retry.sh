#!/usr/bin/env bash
# Re-run only L5 and L9 from the smoke test, sourcing the helpers from
# the original script.
set -uo pipefail

# Pull in helpers and run_level by sourcing — but the original script runs
# everything at the bottom, so just exec it filtered for L5/L9.
source <(sed -n '1,/^run_level 4/p' /home/zelmar/new_EC2/smoketest.sh | head -n -1)
ensure_net
run_level 5  "node3 oplog grows from 990MB to 5GB"
run_level 9  "extract mongod version from FTDC into answer.txt"

echo
echo "==== Summary ===="
for line in "${result_summary[@]}"; do
    printf "  %b\n" "$line"
done
