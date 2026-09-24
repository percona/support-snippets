#!/bin/bash
# This check is a completeness floor, not a grade. There is no correct
# answer to check against — this question is read by a human. The script
# only confirms the candidate actually wrote something substantive, so an
# empty submission is distinguishable from a real one on the dashboard. A
# pass here means "there is a report to read", nothing more; the empty
# `human_graded` marker file next to this script tells the controller to
# leave this question out of the automatic pass count for that reason.
#
# Deliberately NOT keyword-scored: the moment candidates learn a keyword
# list exists, the question stops measuring understanding and starts
# measuring vocabulary.
set -e

REPORT="/home/candidate/report.md"

# The container is destroyed the moment the candidate advances, so copy the
# report somewhere that survives. /var/log/history is the volume the
# transcripts live in, and the dashboard reads from it. Each interview run now
# gets its own directory, passed in as HISTDIR
# (/var/log/history/<run_id>/level-<N>), and the dashboard reads the artifact
# from there without falling back to the flat path once a run id exists.
# Honour HISTDIR so the written report lands where the controller looks, and
# keep the old per-level path for a run without one (an older controller, or
# the smoke test).
preserve() {
    local dest="${HISTDIR:-/var/log/history/level-${LEVEL:-11}}"
    mkdir -p "$dest" 2>/dev/null || return 0
    cp -f "$REPORT" "$dest/report.md" 2>/dev/null || true
}
trap preserve EXIT
MIN_CHARS=300
MIN_LINES=4

if [ ! -s "$REPORT" ]; then
    echo "Not solved: $REPORT is empty or missing."
    exit 1
fi

chars=$(tr -d '[:space:]' < "$REPORT" | wc -c | tr -d ' ')
lines=$(grep -cve '^[[:space:]]*$' "$REPORT" | tr -d ' ')

if [ "$chars" -lt "$MIN_CHARS" ] || [ "$lines" -lt "$MIN_LINES" ]; then
    echo "Not solved: the report is too short to be an assessment"
    echo "(${chars} characters over ${lines} lines; expected at least ${MIN_CHARS} and ${MIN_LINES})."
    exit 1
fi

exit 0
