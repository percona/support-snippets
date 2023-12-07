#!/bin/bash

# - Capture slow query log / audit log for some time (5 - 30 minutes)
# - Using pt-query-digest --sample <N> --no-report;  to extract samples of each type of queries;
# - Split the output in one query per file (.sql file must contain appropriate USE <db>;  filaname should be pt-query-digest fingerprint + sequence # + .sql)
# Then on a replica:

INTERVAL=1; # how often to check results
ITERATIONS=10; # how many consecutive checks to perform
CYCLES=5; # how many consecutive identical hashes to consider as candidate
          # For example, if the sql gets the same result for more than 5 times, the sql will be in the QUERIES_CANDIDATES_FOLDER

# Configure mysql user and password
MYSQL="mysql "

QUERIES_FOLDER="${HOME}/queries_for_caching_evaluation/pending";
QUERIES_DONE_FOLDER="${HOME}/queries_for_caching_evaluation/done";
QUERIES_CANDIDATES_FOLDER="${HOME}/queries_for_caching_evaluation/candidates";

for query_file in "${QUERIES_FOLDER}"/*.sql ; do {
    query_file=$(basename "${query_file}")
    cycle=0;
    iteration=0;
    while [[ ${iteration} -lt ${ITERATIONS} ]]; do {
        checksum=$(${MYSQL} --quick < "${QUERIES_FOLDER}/${query_file}" | md5sum | awk '{print $1}');
        if [[ -n "${last_checksum}" ]]; then {
            if [[ "${last_checksum}" == "${checksum}" ]]; then {
                cycle=$((cycle+1));
            } else {
                cycle=0;
            } fi;
        } fi;

        if [[ ${cycle} -ge ${CYCLES} ]]; then {
            break;
        } fi;

        last_checksum="${checksum}";
        iteration=$((iteration+1));
        sleep ${INTERVAL};
    } done;
    mv -v "${QUERIES_FOLDER}/${query_file}" "${QUERIES_DONE_FOLDER}/${query_file}";
    if [[ ${cycle} -ge ${CYCLES} ]]; then {
        ln -vs "${QUERIES_DONE_FOLDER}/${query_file}" "${QUERIES_CANDIDATES_FOLDER}/${query_file}";
    } fi;

} done;
