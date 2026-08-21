#!/bin/bash
# Regenerate candidate-exercises.txt from the per-question README files, so
# the interviewer copy never drifts from what the candidate sees.
#   ./tools/dump-questions.sh > candidate-exercises.txt
set -e
cd "$(dirname "$0")/.."

cat <<'HDR'
================================================================
  Support Engineer Interview Lab — candidate-facing questions
  (the ticket text shown in the left panel for each question)
================================================================
HDR

for d in exercises/[0-9][0-9]-*/; do
    name=$(basename "$d")
    printf '\n\n'
    echo "----------------------------------------------------------------"
    echo "  $name"
    echo "----------------------------------------------------------------"
    printf '\n'
    cat "$d/README.md"
done
