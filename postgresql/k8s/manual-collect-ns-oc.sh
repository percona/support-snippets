#!/usr/bin/env bash
# Usage: bash manual-collect-ns-oc.sh <namespace>
NS=${1:?usage: $0 <namespace>}

rm -rf cluster-dump
mkdir -p cluster-dump/cluster-scope cluster-dump/$NS

# dump <file> <command...>: writes the command's YAML output to <file>.
# If the command fails, <file> gets the reason as YAML comments instead.
dump() {
  local out=$1; shift
  local err
  if err=$("$@" -o yaml 2>&1 >"$out"); then
    [ -n "$err" ] && echo "$err" >&2
    return 0
  fi
  echo "$err" >&2
  if grep -qi forbidden <<<"$err"; then
    echo "# NOT COLLECTED: the user has no privileges to list this resource" >"$out"
  else
    echo "# NOT COLLECTED: the resource could not be listed" >"$out"
  fi
  sed 's/^/# /' <<<"$err" >>"$out"
}

# pg_gather script: always downloaded fresh, removed on exit
GATHER_URL=https://raw.githubusercontent.com/percona/support-snippets/master/postgresql/pg_gather/gather.sql
GATHER=$(mktemp)
trap 'rm -f "$GATHER"' EXIT
if ! GATHER_ERR=$(curl -fsSL "$GATHER_URL" -o "$GATHER" 2>&1); then
  GATHER_ERR="gather.sql could not be downloaded from $GATHER_URL: $GATHER_ERR"
elif ! head -1 "$GATHER" | grep -q pg_gather; then
  GATHER_ERR="the file downloaded from $GATHER_URL is not pg_gather's gather.sql"
else
  GATHER_ERR=
fi
if [ -n "$GATHER_ERR" ]; then
  echo "WARNING: $GATHER_ERR; pg_gather summaries will not be collected" >&2
  rm -f "$GATHER"; GATHER=
fi

# 1. Cluster-scoped resources
for r in $(oc api-resources --namespaced=false --verbs=list -o name); do
  dump cluster-dump/cluster-scope/$r.yaml oc get $r
done

# 2. Namespaced resources (except secrets)
for r in $(oc api-resources --namespaced=true --verbs=list -o name | grep -vx secrets); do
  dump cluster-dump/$NS/$r.yaml oc -n $NS get $r
done

# 3. TLS certificates
for s in $(oc -n $NS get secrets -o jsonpath='{range .items[?(@.data.tls\.crt)]}{.metadata.name}{"\n"}{end}'); do
  oc -n $NS get secret $s -o jsonpath='{.data.tls\.crt}' | base64 -d > cluster-dump/$NS/$s
done

# 4. Every pod: logs of every container and describe
for p in $(oc -n $NS get pods -o name | cut -d/ -f2); do
  mkdir -p cluster-dump/$NS/$p
  for c in $(oc -n $NS get pod $p -o jsonpath='{range .spec.initContainers[*]}{.name}{"\n"}{end}{range .spec.containers[*]}{.name}{"\n"}{end}'); do
    oc -n $NS logs $p -c $c > cluster-dump/$NS/$p/$c.log
  done
  oc -n $NS describe pod $p > cluster-dump/$NS/$p/describe.txt
done

# 5. Running PostgreSQL instance pods
for p in $(oc -n $NS get pods -l pgv2.percona.com/version,postgres-operator.crunchydata.com/instance --field-selector=status.phase=Running -o name | cut -d/ -f2); do
  oc -n $NS exec $p -c database -- patronictl list > cluster-dump/$NS/$p/patronictl-list.log
  oc -n $NS exec $p -c database -- pgbackrest info > cluster-dump/$NS/$p/pgbackrest-info.log
  oc -n $NS exec $p -c database -- bash -c 'd=$(psql -XAtc "SHOW log_directory"); case "$d" in /*) ;; "") d=$PGDATA/log;; *) d=$PGDATA/$d;; esac; tar cf - "$d"' > cluster-dump/$NS/$p/pg_log.tar
  oc -n $NS exec $p -c database -- tar cf - /pgdata/pgbackrest/log > cluster-dump/$NS/$p/pgbackrest_log.tar
  if [ -n "$GATHER" ]; then
    oc -n $NS exec -i $p -c database -- psql -X -f - < "$GATHER" > cluster-dump/$NS/$p/summary.txt
  else
    echo "# NOT COLLECTED: $GATHER_ERR" > cluster-dump/$NS/$p/summary.txt
  fi
done

# 6. Package
tar czf cluster-dump_${NS}_$(date -u +%Y%m%d%H%M%S).tar.gz cluster-dump
