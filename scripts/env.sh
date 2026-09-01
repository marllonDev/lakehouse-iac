# Put this project's pinned CLIs, virtualenv, and Databricks connection settings
# on the current shell.
#
# Usage: source scripts/env.sh
#
# Nothing here is a secret. The workspace host is read from the Databricks CLI
# profile and the warehouse from Terraform's outputs, so this file holds no
# account-specific values and the repository stays portable.
#
# Override anything by exporting it before sourcing:
#   DATABRICKS_CONFIG_PROFILE=OTHER source scripts/env.sh

_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

export PATH="$_root/.bin:$_root/.venv/bin:$PATH"
export AI_DEV_KIT_HOME="$_root/tools/ai-dev-kit"

export DATABRICKS_CONFIG_PROFILE="${DATABRICKS_CONFIG_PROFILE:-FREE}"

# Host comes from the CLI profile written by `databricks auth login`.
if [ -z "${DATABRICKS_HOST:-}" ] && [ -r "$HOME/.databrickscfg" ]; then
  DATABRICKS_HOST="$(
    awk -v profile="[$DATABRICKS_CONFIG_PROFILE]" '
      $0 == profile { found = 1; next }
      /^\[/         { found = 0 }
      found && $1 == "host" { print $3; exit }
    ' "$HOME/.databrickscfg"
  )"
  [ -n "$DATABRICKS_HOST" ] && export DATABRICKS_HOST
fi

# HTTP path comes from Terraform, so dbt and the job always agree on which
# warehouse they are talking to. Falls back silently before the first apply.
if [ -z "${DATABRICKS_HTTP_PATH:-}" ] && [ -f "$_root/infra/terraform.tfstate" ]; then
  DATABRICKS_HTTP_PATH="$(
    "$_root/.bin/terraform" -chdir="$_root/infra" output -raw dbt_http_path 2>/dev/null
  )"
  [ -n "$DATABRICKS_HTTP_PATH" ] && export DATABRICKS_HTTP_PATH
fi

export DBT_PROFILES_DIR="$_root/transform"
export DBT_CATALOG="${DBT_CATALOG:-dev_lakehouse}"

if [ -z "${DATABRICKS_HOST:-}" ]; then
  echo "env.sh: no host found for profile '$DATABRICKS_CONFIG_PROFILE'." >&2
  echo "        Run: databricks auth login --host <workspace-url> --profile $DATABRICKS_CONFIG_PROFILE" >&2
fi

if [ -z "${DATABRICKS_HTTP_PATH:-}" ]; then
  echo "env.sh: no warehouse path yet. Run terraform apply, then source this again." >&2
fi

unset _root
