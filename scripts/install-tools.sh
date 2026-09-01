#!/usr/bin/env bash
#
# Installs every CLI this project needs into ./.bin and ./.venv.
# Nothing is installed system-wide; deleting the repo removes all of it.
#
# Requires: uv (https://docs.astral.sh/uv/), curl, unzip.
#
set -euo pipefail

TERRAFORM_VERSION="1.16.0"
DATABRICKS_CLI_VERSION="1.14.1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.bin"
mkdir -p "$BIN"

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64)        ARCH="amd64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

fetch_zip() {
  local url="$1" tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/pkg.zip"
  unzip -qo "$tmp/pkg.zip" -d "$tmp"
  find "$tmp" -maxdepth 2 -type f -perm -u+x ! -name '*.zip' -exec cp {} "$BIN/" \;
  rm -rf "$tmp"
}

echo "==> terraform ${TERRAFORM_VERSION}"
fetch_zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"

echo "==> databricks CLI ${DATABRICKS_CLI_VERSION}"
fetch_zip "https://github.com/databricks/cli/releases/download/v${DATABRICKS_CLI_VERSION}/databricks_cli_${DATABRICKS_CLI_VERSION}_${OS}_${ARCH}.zip"

echo "==> dbt-databricks (project virtualenv)"
cd "$ROOT"
uv sync --quiet

echo
echo "Installed:"
"$BIN/terraform" version | head -1
"$BIN/databricks" --version
"$ROOT/.venv/bin/dbt" --version 2>&1 | head -2
echo
echo 'Add the tools to your shell with: source scripts/env.sh'
