#!/bin/bash
set -e

# Stage the tarball where the application team "delivered" it.
install -m 644 -o candidate -g candidate \
    /opt/company.json.tar.gz /tmp/company.json.tar.gz
