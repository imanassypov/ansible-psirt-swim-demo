#!/usr/bin/env bash
# Start the self-hosted Actions runner if it is installed but not running.
# Safe to call repeatedly (e.g. on every cd into the repo via direnv).
#
# Usage:
#   ./scripts/ensure-actions-runner.sh
#   ./scripts/ensure-actions-runner.sh --quiet
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_DIR="$REPO_ROOT/.github/actions-runner"
LOCK_DIR="$RUNNER_DIR/.ensure.lock"
QUIET=false

if [[ "${1:-}" == "--quiet" ]]; then
  QUIET=true
fi

log() {
  if [[ "$QUIET" == false ]]; then
    echo "$@"
  fi
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

if [[ ! -f "$RUNNER_DIR/.runner" || ! -x "$RUNNER_DIR/run.sh" ]]; then
  log "Actions runner not installed. Run: ./scripts/setup-actions-runner.sh"
  exit 0
fi

LISTENER="$RUNNER_DIR/bin/Runner.Listener"
if pgrep -f "${LISTENER} run" >/dev/null 2>&1; then
  log "Actions runner already running."
  exit 0
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Actions runner start already in progress."
  exit 0
fi
trap release_lock EXIT

# Re-check after acquiring lock (another shell may have started it).
if pgrep -f "${LISTENER} run" >/dev/null 2>&1; then
  log "Actions runner already running."
  exit 0
fi

log "Starting Actions runner..."
cd "$RUNNER_DIR"
nohup ./run.sh >> runner-console.log 2>&1 &
disown -h 2>/dev/null || true
log "Started PID $! (logs: $RUNNER_DIR/runner-console.log)"
release_lock
trap - EXIT
