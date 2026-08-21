#!/bin/bash
# Runs once at container startup, after mongod is up. Use it to load fixture
# data, break the state the candidate must fix, create users, etc.
set -e

mongosh --quiet mongodb://127.0.0.1:27017/admin <<'EOF'
// Example: insert seed data.
// db.getSiblingDB("demo").widgets.insertMany([{ name: "alpha" }, { name: "beta" }]);
EOF
