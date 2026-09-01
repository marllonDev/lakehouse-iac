# Put this project's pinned CLIs, virtualenv, and Databricks connection settings
# on the current shell. Everything here is non-secret; the OAuth token itself is
# held by the Databricks CLI under ~/.databrickscfg.
#
# Usage: source scripts/env.sh
_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

export PATH="$_root/.bin:$_root/.venv/bin:$PATH"
export AI_DEV_KIT_HOME="$_root/tools/ai-dev-kit"

export DATABRICKS_CONFIG_PROFILE="${DATABRICKS_CONFIG_PROFILE:-FREE}"
export DATABRICKS_HOST="${DATABRICKS_HOST:-https://dbc-a6fd4338-3962.cloud.databricks.com}"
export DATABRICKS_HTTP_PATH="${DATABRICKS_HTTP_PATH:-/sql/1.0/warehouses/7dd59f8f8f572625}"

export DBT_PROFILES_DIR="$_root/transform"
export DBT_CATALOG="${DBT_CATALOG:-dev_lakehouse}"

unset _root
