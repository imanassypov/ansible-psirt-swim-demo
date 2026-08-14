#!/usr/bin/env bash
# Copy SWIM evidence JSON from ansible/logs/ into reports/<run-label>/ and render
# a human-readable summary markdown for the change ticket / audit trail.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOGS_DIR="$REPO_ROOT/ansible/logs"
REPORTS_DIR="$REPO_ROOT/reports"
RUN_LABEL="${1:-$(date +%Y%m%d-%H%M%S)}"
SINCE_EPOCH="${2:-0}"

if [[ -f "${REPO_ROOT}/scripts/ci/lib/log.sh" ]]; then
  # shellcheck source=ci/lib/log.sh
  source "${REPO_ROOT}/scripts/ci/lib/log.sh"
  log() { ci_log "$@"; }
else
  log() { echo "$@"; }
fi

DEST="$REPORTS_DIR/$RUN_LABEL"
mkdir -p "$DEST"

if [[ ! -d "$LOGS_DIR" ]]; then
  log "ERROR: logs directory not found."
  exit 1
fi

copied=0
MARKER="$(mktemp)"
if [[ "$SINCE_EPOCH" =~ ^[0-9]+$ ]] && [[ "$SINCE_EPOCH" -gt 0 ]]; then
  if date -r "$SINCE_EPOCH" >/dev/null 2>&1; then
    touch -t "$(date -r "$SINCE_EPOCH" +%Y%m%d%H%M.%S)" "$MARKER"
  else
    touch -d "@${SINCE_EPOCH}" "$MARKER"
  fi
  while IFS= read -r -d '' file; do
    cp "$file" "$DEST/"
    copied=$((copied + 1))
  done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name '*.json' -newer "$MARKER" -print0)
else
  while IFS= read -r -d '' file; do
    cp "$file" "$DEST/"
    copied=$((copied + 1))
  done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name '*.json' -print0)
fi
rm -f "$MARKER"

if [[ "$copied" -eq 0 ]]; then
  log "WARNING: no evidence JSON files found for this pipeline window."
fi

python3 "$REPO_ROOT/scripts/render-swim-report.py" "$DEST"

log "Collected ${copied} evidence file(s) into reports/${RUN_LABEL}/"
