#!/usr/bin/env bash
# Generate the nginx HTTP basic-auth files for the lab.
#
#   nginx/auth/htpasswd              shared "candidate" cred + the interviewer
#                                    cred — gates the WHOLE site so a public IP
#                                    isn't wide open.
#   nginx/auth/htpasswd-interviewer  interviewer cred only — gates /interviewer/
#                                    and /reset so candidates can't peek at the
#                                    dashboard or reset progress.
#
# Credentials come from env vars, or you'll be prompted:
#   CANDIDATE_USER   (default: candidate)     CANDIDATE_PASS
#   INTERVIEWER_USER (default: interviewer)   INTERVIEWER_PASS
#
# Re-run any time to rotate passwords, then restart nginx:
#   ./gen-auth.sh && docker compose restart nginx
set -euo pipefail
cd "$(dirname "$0")"

command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

AUTH_DIR="nginx/auth"
mkdir -p "$AUTH_DIR"

CANDIDATE_USER="${CANDIDATE_USER:-candidate}"
INTERVIEWER_USER="${INTERVIEWER_USER:-interviewer}"

if [ -z "${CANDIDATE_PASS:-}" ]; then
    read -rsp "Password for candidate user '${CANDIDATE_USER}': " CANDIDATE_PASS; echo
fi
if [ -z "${INTERVIEWER_PASS:-}" ]; then
    read -rsp "Password for interviewer user '${INTERVIEWER_USER}': " INTERVIEWER_PASS; echo
fi

cand_hash="$(openssl passwd -apr1 "$CANDIDATE_PASS")"
intv_hash="$(openssl passwd -apr1 "$INTERVIEWER_PASS")"

# Site-wide: both users (the interviewer must be valid here too, so loading
# /static while on the dashboard doesn't trigger a second auth prompt).
{
    printf '%s:%s\n' "$CANDIDATE_USER" "$cand_hash"
    printf '%s:%s\n' "$INTERVIEWER_USER" "$intv_hash"
} > "$AUTH_DIR/htpasswd"

# Interviewer-only: /interviewer/ + /reset.
printf '%s:%s\n' "$INTERVIEWER_USER" "$intv_hash" > "$AUTH_DIR/htpasswd-interviewer"

chmod 644 "$AUTH_DIR/htpasswd" "$AUTH_DIR/htpasswd-interviewer"

echo "Wrote $AUTH_DIR/htpasswd and $AUTH_DIR/htpasswd-interviewer"
echo "  candidate login:   $CANDIDATE_USER"
echo "  interviewer login: $INTERVIEWER_USER  (also works on the candidate site + dashboard)"
