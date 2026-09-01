#!/usr/bin/env bash
#
# Generates the dbt docs static site and publishes it to the gh-pages branch,
# which GitHub Pages serves as-is: no build step, no server, just files.
#
# Deliberately run by a human, not by CI. `dbt docs generate` connects to the
# warehouse to read real column types and table stats into catalog.json — the
# same reason this project's CI never carries Databricks credentials (see
# .github/workflows/ci.yml). Terraform's apply draws the same line for the
# same reason; this script draws it again for docs.
#
# Usage:
#   source scripts/env.sh
#   scripts/publish-docs.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="gh-pages"
WORKTREE="$(mktemp -d)"
trap 'rm -rf "$WORKTREE"; cd "$ROOT" && git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true' EXIT

echo "==> Generating docs (needs a live warehouse connection)"
( cd "$ROOT/transform" && dbt docs generate )

for f in index.html manifest.json catalog.json; do
  [ -f "$ROOT/transform/target/$f" ] || { echo "missing transform/target/$f — did dbt docs generate fail?" >&2; exit 1; }
done

echo "==> Preparing the $BRANCH worktree"
cd "$ROOT"
git fetch origin "$BRANCH" >/dev/null 2>&1 || true

rm -rf "$WORKTREE"
if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git worktree add "$WORKTREE" "$BRANCH" >/dev/null
else
  git worktree add --detach "$WORKTREE" >/dev/null
  ( cd "$WORKTREE" && git checkout --orphan "$BRANCH" >/dev/null && git rm -rf . >/dev/null 2>&1 || true )
fi

echo "==> Copying the generated site"
find "$WORKTREE" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp "$ROOT/transform/target/index.html" "$WORKTREE/"
cp "$ROOT/transform/target/manifest.json" "$WORKTREE/"
cp "$ROOT/transform/target/catalog.json" "$WORKTREE/"

# Without this, GitHub Pages runs the site through Jekyll, which ignores any
# path starting with an underscore — dbt's docs bundle uses exactly that.
touch "$WORKTREE/.nojekyll"

cd "$WORKTREE"
git add -A
if git diff --cached --quiet; then
  echo "==> Nothing changed, not publishing"
else
  git -c user.name="${GIT_AUTHOR_NAME:-lakehouse-iac}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-noreply@users.noreply.github.com}" \
      commit -q -m "docs: publish dbt docs ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  git push origin "$BRANCH"
  echo "==> Published to $BRANCH"
fi
