#!/usr/bin/env bash
#
# Vendors the Databricks MCP server from databricks-solutions/ai-dev-kit under
# tools/ai-dev-kit/ with its own virtualenv. Optional: only needed if you want
# the project-scoped MCP server declared in .mcp.json.
#
# Databricks agent skills are deliberately not handled here. They are installed
# once per machine, not per repository:
#
#   databricks aitools install --agents claude-code --scope global
#
# tools/ai-dev-kit/ is gitignored, so run this once after cloning the repo.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Vendoring the Databricks MCP server into tools/ai-dev-kit/"
git clone --depth 1 -q https://github.com/databricks-solutions/ai-dev-kit.git "$WORK/ai-dev-kit"
rm -rf "$WORK/ai-dev-kit/.git" "$ROOT/tools/ai-dev-kit"
mkdir -p "$ROOT/tools"
cp -R "$WORK/ai-dev-kit" "$ROOT/tools/ai-dev-kit"

echo "==> Building the MCP server virtualenv (requires uv)"
bash "$ROOT/tools/ai-dev-kit/databricks-mcp-server/setup.sh" --quiet

echo "==> Done. Configure a Databricks CLI profile, then set DATABRICKS_CONFIG_PROFILE."
