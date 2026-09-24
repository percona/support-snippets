#!/bin/bash
# Pass when BOTH tasks are done:
#   1. mysqld is up and answering on 3306, and
#   2. answer.txt holds the number of connections held by 'appuser'.
#
# Counting a named application account rather than every session is the skill
# being tested: the candidate's own terminal tabs (which connect as candidate
# or root) must not be included. The live comparison therefore filters by
# USER='appuser', and the tolerance is tight so an answer that counted every
# session (Threads_connected) rather than just the application's does not slip
# through. A single worker caught mid-reconnect is still absorbed.
#
# A floor guards against "solving" the second task by stopping the pool and
# writing 0: if the application is barely connected at all, the pool was killed
# rather than counted, and that is not the answer.
set -e

ANSWER_FILE="/home/candidate/answer.txt"
TOLERANCE=1
MIN_LIVE=20

if ! mysqladmin -uroot -h 127.0.0.1 -P 3306 --protocol=tcp ping >/dev/null 2>&1; then
    echo "Not solved: mysqld is not answering on 127.0.0.1:3306."
    exit 1
fi

if [ ! -s "$ANSWER_FILE" ]; then
    echo "Not solved: $ANSWER_FILE is empty or missing (write the appuser connection count there)."
    exit 1
fi

candidate=$(tr -cd '0-9' < "$ANSWER_FILE")
if [ -z "$candidate" ]; then
    echo "Not solved: $ANSWER_FILE does not contain a number."
    exit 1
fi

live=$(mysql -uroot -N -B -e \
    "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE USER='appuser';" \
    2>/dev/null | tr -cd '0-9')
if [ -z "$live" ]; then
    echo "Not solved: could not read the processlist from mysqld."
    exit 1
fi

if [ "$live" -lt "$MIN_LIVE" ] 2>/dev/null; then
    echo "Not solved: only $live appuser connections are live — the application pool"
    echo "is not running. It should be counted while it holds its connections, not stopped."
    exit 1
fi

diff=$(( candidate - live )); diff=${diff#-}
if [ "$diff" -le "$TOLERANCE" ]; then
    exit 0
fi

echo "Not solved: the number in $ANSWER_FILE does not match the connections appuser is holding."
echo "Count only the sessions whose user is 'appuser', not every connection."
exit 1
