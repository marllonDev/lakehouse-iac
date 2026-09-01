#!/usr/bin/env bash
#
# Bootstraps the local agent tooling this project depends on:
#   1. Databricks agent skills, installed project-scoped under .claude/skills/
#   2. The Databricks MCP server from databricks-solutions/ai-dev-kit, vendored
#      under tools/ai-dev-kit/ with its own virtualenv
#
# Both directories are gitignored, so run this once after cloning the repo.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Installing Databricks agent skills into .claude/skills/"
git clone --depth 1 -q https://github.com/databricks/databricks-agent-skills.git "$WORK/skills"
mkdir -p "$ROOT/.claude/skills"
cp -R "$WORK/skills/plugins/databricks/claude/skills/." "$ROOT/.claude/skills/"
echo "    $(find "$ROOT/.claude/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') skills installed"

echo "==> Vendoring the Databricks MCP server into tools/ai-dev-kit/"
git clone --depth 1 -q https://github.com/databricks-solutions/ai-dev-kit.git "$WORK/ai-dev-kit"
rm -rf "$WORK/ai-dev-kit/.git" "$ROOT/tools/ai-dev-kit"
mkdir -p "$ROOT/tools"
cp -R "$WORK/ai-dev-kit" "$ROOT/tools/ai-dev-kit"

echo "==> Building the MCP server virtualenv (requires uv)"
bash "$ROOT/tools/ai-dev-kit/databricks-mcp-server/setup.sh" --quiet

echo "==> Done. Configure a Databricks CLI profile, then set DATABRICKS_CONFIG_PROFILE."
