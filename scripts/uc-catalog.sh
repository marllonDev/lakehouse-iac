#!/usr/bin/env bash
#
# Creates or drops a Unity Catalog catalog through the SQL Statement API.
#
# Terraform normally does this with the databricks_catalog resource, but on
# Databricks Free Edition the Unity Catalog REST endpoint rejects the call:
#
#   Metastore storage root URL does not exist. Default Storage is enabled in
#   your account. You can use the UI to create a new catalog using Default
#   Storage, or please provide a storage location for the catalog.
#
# There is no storage location to provide — Free Edition has no cloud account
# attached — but the equivalent SQL statement resolves Default Storage on its
# own and succeeds. So Terraform shells out to this script for the catalog and
# manages everything inside it (schemas, grants) natively.
#
# Usage: uc-catalog.sh {create|drop} <catalog_name>
# Env:   DATABRICKS_CONFIG_PROFILE, WAREHOUSE_ID
#
set -euo pipefail

USAGE="usage: uc-catalog.sh create|drop <catalog_name>"
ACTION="${1:?$USAGE}"
CATALOG="${2:?$USAGE}"

: "${WAREHOUSE_ID:?WAREHOUSE_ID must be set}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/.bin/databricks"
[ -x "$CLI" ] || CLI="$(command -v databricks)"

case "$ACTION" in
  create) STATEMENT="CREATE CATALOG IF NOT EXISTS \`${CATALOG}\`" ;;
  drop)   STATEMENT="DROP CATALOG IF EXISTS \`${CATALOG}\` CASCADE" ;;
  *) echo "unknown action: $ACTION" >&2; exit 1 ;;
esac

RESPONSE="$(
  "$CLI" api post /api/2.0/sql/statements --json "$(
    printf '{"warehouse_id":"%s","statement":"%s","wait_timeout":"50s"}' \
      "$WAREHOUSE_ID" "$STATEMENT"
  )"
)"

STATE="$(printf '%s' "$RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"]["state"])')"

if [ "$STATE" != "SUCCEEDED" ]; then
  echo "catalog $ACTION failed (state=$STATE):" >&2
  printf '%s\n' "$RESPONSE" >&2
  exit 1
fi

echo "catalog $ACTION succeeded: $CATALOG"
