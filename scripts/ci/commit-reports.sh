#!/usr/bin/env bash
# Sanitize, verify, and commit the current workflow's report directory only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ci_cd_lab

RUN_LABEL="${GITHUB_RUN_NUMBER:-}-${GITHUB_RUN_ID:-}"
if [[ -z "${GITHUB_RUN_NUMBER:-}" || -z "${GITHUB_RUN_ID:-}" ]]; then
  ci_log "ERROR: GITHUB_RUN_NUMBER and GITHUB_RUN_ID are required."
  exit 1
fi

REPORT_DIR="reports/${RUN_LABEL}"
if [[ ! -d "$REPORT_DIR" ]]; then
  ci_log "No report directory for this run; nothing to commit."
  exit 0
fi

bash "${SWIM_LAB_ROOT}/scripts/verify-report-artifacts.sh" "$REPORT_DIR"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# The pipeline runs at the trigger SHA, which may trail master (e.g. re-runs of
# an older run). Rebase onto the remote tip so the report commit fast-forwards.
# Untracked artifacts for this run survive the forced checkout.
git fetch -q origin master
git checkout -q -f -B master origin/master

# Keep only the current run on master — remove previously committed run folders.
while IFS= read -r -d '' old_dir; do
  old_label="$(basename "$old_dir")"
  [[ "$old_label" =~ ^[0-9]+-[0-9]+$ ]] || continue
  [[ "$old_label" == "$RUN_LABEL" ]] && continue
  if git ls-files --error-unmatch "$old_dir" >/dev/null 2>&1; then
    git rm -rf "$old_dir"
  else
    rm -rf "$old_dir"
  fi
  ci_log "Removed stale report directory reports/${old_label}/"
done < <(find reports -mindepth 1 -maxdepth 1 -type d -print0)

git add "$REPORT_DIR"

if git diff --cached --quiet; then
  ci_log "No new report artifacts to commit."
  exit 0
fi

git commit -m "$(cat <<EOF
chore(reports): SWIM pipeline evidence for run ${GITHUB_RUN_NUMBER}

Sanitized report artifacts (no local paths or customer identifiers).
Workflow run: ${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ID}
Commit: ${GITHUB_SHA}
EOF
)"

git push origin HEAD:master
ci_log "Reports committed and pushed for workflow run ${GITHUB_RUN_NUMBER}."
