#!/usr/bin/env bash
# Thin wrapper around the Liquibase CLI. Whatever args you pass become the
# Liquibase command — `update`, `status`, `tag <name>`, `rollback <tag>`,
# `drop-all`, `release-locks`, etc.
#
# Required env (compose injects these):
#   DB_URL    JDBC connection string
#   DB_USER   username
#   DB_PASS   password
# Optional:
#   CHANGELOG path inside the container (default /workspace/changelog/db.changelog-master.xml)
set -euo pipefail

: "${DB_URL:?DB_URL is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASS:?DB_PASS is required}"

# Relative path under WORKDIR=/workspace. Matches Spring Boot's classpath
# resolution so DATABASECHANGELOG.FILENAME stays consistent.
CHANGELOG="${CHANGELOG:-db/changelog/db.changelog-master.xml}"

if [[ ! -f "/workspace/$CHANGELOG" && ! -f "$CHANGELOG" ]]; then
  echo "Changelog not found at /workspace/$CHANGELOG. Did you mount the volume?" >&2
  exit 1
fi

exec liquibase \
  --changelog-file="$CHANGELOG" \
  --url="$DB_URL" \
  --username="$DB_USER" \
  --password="$DB_PASS" \
  "$@"
