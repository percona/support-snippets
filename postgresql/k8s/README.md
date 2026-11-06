# PostgreSQL on Kubernetes: namespace-scoped diagnostic collection

This folder contains two Bash scripts that collect diagnostic data from a
[Percona Operator for PostgreSQL](https://docs.percona.com/percona-operator-for-postgresql/)
(v2) deployment, limited to a single namespace.

They are a temporary workaround for
[PT-2586](https://perconadev.atlassian.net/browse/PT-2586): when
[`pt-k8s-debug-collector`](https://docs.percona.com/percona-toolkit/pt-k8s-debug-collector.html)
is asked for one namespace, it does not filter correctly. The scripts collect
the same kind of data the tool collects for PostgreSQL, but only from the
namespace you pass. Use them until PT-2586 is fixed.

## Files

| File | Use it with |
|------|-------------|
| `manual-collect-ns-kubectl.sh` | Kubernetes clusters (`kubectl`) |
| `manual-collect-ns-oc.sh` | OpenShift clusters (`oc`) |

The two scripts are identical except for the CLI they call.

## Requirements

- `bash`, `curl`, `tar`, `base64`, `sed`, `grep`, `cut`, `mktemp`.
- `kubectl` or `oc`, already logged in to the cluster, with a context that can
  read the target namespace and `exec` into its pods.
- Outbound HTTPS access to `raw.githubusercontent.com`, to download
  [pg_gather](../pg_gather/)'s `gather.sql` (see below). Without it, the
  collection still runs, only the pg_gather summaries are skipped.

### pg_gather download

On every run, the script downloads the latest
[`gather.sql`](../pg_gather/gather.sql) from this repository into a temporary
file, which is removed when the script exits. There is nothing to download
beforehand. The file is streamed into `psql` on each running PostgreSQL pod to
produce `summary.txt`.

If the download fails, or the downloaded file is not pg_gather's `gather.sql`,
the script prints a warning and continues. Each `summary.txt` then contains a
`# NOT COLLECTED: ...` line with the reason, and everything else is collected
normally.

## Usage

```bash
# Kubernetes
bash manual-collect-ns-kubectl.sh <namespace>

# OpenShift
bash manual-collect-ns-oc.sh <namespace>
```

The script writes everything under `./cluster-dump` and then packages it as
`cluster-dump_<namespace>_<UTC timestamp>.tar.gz` in the current directory.
Send that file to Percona Support.

> **Warning:** the script deletes any existing `./cluster-dump` directory in
> the current working directory before it starts. Run it from an empty or
> dedicated directory.

## What it collects

1. **Cluster-scoped resources** (`cluster-dump/cluster-scope/<resource>.yaml`):
   every listable non-namespaced resource type (nodes, storage classes, CRDs,
   and so on).
2. **Namespaced resources** (`cluster-dump/<namespace>/<resource>.yaml`): every
   listable resource type in the namespace, **except `secrets`**.
3. **TLS certificates** (`cluster-dump/<namespace>/<secret name>`): only the
   public `tls.crt` of each secret that has one. Private keys and other secret
   data are not collected.
4. **Every pod in the namespace** (`cluster-dump/<namespace>/<pod>/`): the logs
   of every init container and container (`<container>.log`) and
   `kubectl describe pod` output (`describe.txt`).
5. **Running PostgreSQL instance pods** (pods labelled
   `pgv2.percona.com/version` and `postgres-operator.crunchydata.com/instance`),
   from the `database` container:
   - `patronictl-list.log`: `patronictl list`
   - `pgbackrest-info.log`: `pgbackrest info`
   - `pg_log.tar`: the PostgreSQL log directory (`log_directory`, resolved
     against `$PGDATA` when relative)
   - `pgbackrest_log.tar`: `/pgdata/pgbackrest/log`
   - `summary.txt`: pg_gather output (see [pg_gather download](#pg_gather-download))
6. **Package**: `cluster-dump_<namespace>_<timestamp>.tar.gz`.

## Missing privileges

If the user cannot list a resource type, the script does not stop. The
corresponding `.yaml` file is written with a comment that explains why it is
empty, followed by the original error:

```yaml
# NOT COLLECTED: the user has no privileges to list this resource
# Error from server (Forbidden): ...
```

Other listing failures are marked `# NOT COLLECTED: the resource could not be
listed`. Errors are also printed to stderr while the script runs.
