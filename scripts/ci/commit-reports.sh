#!/usr/bin/env bash
# CI: commit generated reports back to the repository.
set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add reports/
if git diff --cached --quiet; then
  echo "No new report artifacts to commit."
  exit 0
fi
git commit -m "$(cat <<EOF
chore(reports): SWIM pipeline evidence for settings.json change

Workflow run: ${GITHUB_RUN_NUMBER}
Commit: ${GITHUB_SHA}
EOF
)"
git push
