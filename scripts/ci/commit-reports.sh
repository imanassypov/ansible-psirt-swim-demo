#!/usr/bin/env bash
# Commit generated reports (no local paths in log output).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ci_cd_lab

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add reports/

if git diff --cached --quiet; then
  ci_log "No new report artifacts to commit."
  exit 0
fi

git commit -m "$(cat <<EOF
chore(reports): SWIM pipeline evidence for settings.json change

Workflow run: ${GITHUB_RUN_NUMBER}
Commit: ${GITHUB_SHA}
EOF
)"

git push
ci_log "Reports committed and pushed for workflow run ${GITHUB_RUN_NUMBER}."
