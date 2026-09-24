#!/usr/bin/env bash
# Stage the `employees` sample database for the base image build.
#
# This is the genuine datacharmer/test_db dataset, not a lookalike: the
# questions reference real names and values from it, which a generated
# dataset would not contain.
#
# Like the old company fixture, it is fetched rather than committed — the
# tarball is git-ignored and build.sh calls this when it is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=exercises/_base/employees-db.tar.gz
URL=https://github.com/datacharmer/test_db/archive/refs/heads/master.tar.gz

if [[ -s "$DEST" ]]; then
    echo "employees dataset already staged: $DEST"
    exit 0
fi

echo "==> downloading the employees sample database (~35 MB)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/test_db.tar.gz" "$URL"
tar xzf "$tmp/test_db.tar.gz" -C "$tmp" --strip-components=1

# Keep only what the questions need: the schema, the loaders, and the
# validation file. Drop images, CI config and the partitioned variants.
mkdir -p "$tmp/stage"
cp "$tmp/employees.sql" "$tmp"/load_*.dump "$tmp/show_elapsed.sql" "$tmp/stage/" 2>/dev/null || \
  cp "$tmp/employees.sql" "$tmp"/load_*.dump "$tmp/stage/"
# Pack the files by name rather than `.`. A "./" member carries the staging
# directory's own mode and mtime, and applying that to a directory the
# candidate does not own (they extract into /tmp, which is root-owned and
# sticky) makes GNU tar fail the utime/chmod and exit non-zero — *after*
# writing every file correctly. The data is fine, the exit status is not, and
# it silently breaks `tar xzf ... && mysql < employees.sql`.
#
# --no-xattrs drops the com.apple.provenance attribute macOS stamps on files,
# which GNU tar on the exercise image otherwise reports as an unknown keyword
# once per file. COPYFILE_DISABLE stops bsdtar writing AppleDouble "._"
# companions. Both are understood by GNU tar and bsdtar, so this stays correct
# whether the lab is built from a Mac or from Linux.
# Written straight to the file rather than piped through stdout: bsdtar
# finalises a stdout stream in a way macOS gzip then reports as "trailing
# garbage" on every read. Harmless, but it makes the build look broken.
dest_abs="$PWD/$DEST"
( cd "$tmp/stage" && COPYFILE_DISABLE=1 tar czf "$dest_abs" --no-xattrs -- * )

# The whole point of the above is that a candidate sees a clean extraction, so
# assert it rather than trusting it.
# Counted, not `grep -q`: this script runs under `set -o pipefail`, and a
# short-circuiting grep sends SIGPIPE upstream, which would make the test
# report a failure that never happened.
dot_members=$(tar tzf "$DEST" | grep -cx '\./\?' || true)
if [ "${dot_members:-0}" -gt 0 ]; then
    echo "error: $DEST contains a './' member — it will fail on extract into /tmp" >&2
    exit 1
fi
xattr_hits=$(gzip -dc "$DEST" | grep -ac 'com\.apple' || true)
if [ "${xattr_hits:-0}" -gt 0 ]; then
    echo "error: $DEST carries macOS xattrs — rebuild with --no-xattrs" >&2
    exit 1
fi
echo "    verified: no './' member, no macOS xattrs"

echo "    $DEST ($(du -h "$DEST" | cut -f1))"
echo "    tables: departments, dept_emp, dept_manager, employees, salaries, titles"
