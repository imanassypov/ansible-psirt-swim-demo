#!/usr/bin/env bash
set -euo pipefail

# Cursor stop hook: remind the agent to sync README before finishing.
cat >/dev/null

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

if ./scripts/check-readme-sync.sh >/dev/null 2>&1; then
  exit 0
fi

cat <<'EOF'
{"followup_message":"README.md is out of sync with repository changes. Update README.md (playbook table, directory structure, run commands, troubleshooting, and any new settings) to match the current repo, then run ./scripts/check-readme-sync.sh to verify before finishing."}
EOF
