#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

mkdir -p "$HOOKS_DIR"
ln -sf "$REPO_ROOT/.githooks/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$REPO_ROOT/.githooks/pre-commit" "$REPO_ROOT/scripts/check-readme-sync.sh"

echo "Installed README sync pre-commit hook."
