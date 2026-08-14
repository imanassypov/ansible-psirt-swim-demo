#!/usr/bin/env bash
# Move the Actions runner _work directory to a path without spaces.
# GitHub Actions invokes run: steps as `bash -e {0}`; when {0} lives under a
# path containing spaces, bash splits the script path and every step fails.
#
# Usage (from repository root):
#   ./scripts/fix-runner-workdir.sh
#   ./scripts/fix-runner-workdir.sh --restart
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_DIR="$REPO_ROOT/.github/actions-runner"
RUNNER_CONFIG="$RUNNER_DIR/.runner"
RUNNER_ENV="$RUNNER_DIR/.env"
WORK_ROOT="${GITHUB_ACTIONS_WORK_ROOT:-$HOME/gh-actions-work}"
RESTART=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart) RESTART=true; shift ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$RUNNER_CONFIG" ]]; then
  echo "ERROR: runner not installed at $RUNNER_DIR" >&2
  echo "Run: ./scripts/setup-actions-runner.sh" >&2
  exit 1
fi

mkdir -p "$WORK_ROOT"

python3 - "$RUNNER_CONFIG" "$WORK_ROOT" <<'PY'
import json
import sys

config_path, work_root = sys.argv[1:3]
data = json.loads(open(config_path, encoding="utf-8-sig").read())
old = data.get("workFolder", "_work")
data["workFolder"] = work_root
with open(config_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"Updated workFolder: {old!r} -> {work_root!r}")
PY

# Jobs checkout into ~/gh-actions-work/... — point CI back at this repo for .venv/vault.
{
  echo "SWIM_LAB_ROOT=${REPO_ROOT}"
} > "$RUNNER_ENV"
echo "Wrote SWIM_LAB_ROOT to runner .env (path not printed in logs)."

if [[ "$REPO_ROOT" == *" "* ]]; then
  echo ""
  echo "NOTE: Repository path contains spaces. Work dir moved to: $WORK_ROOT"
  echo "      CI jobs use SWIM_LAB_ROOT to link .venv and vault.yml."
else
  echo ""
  echo "Work dir set to: $WORK_ROOT"
fi

echo ""
echo "Restart the runner:"
echo "  ./scripts/fix-runner-workdir.sh --restart"

if [[ "$RESTART" == true ]]; then
  pkill -f "${RUNNER_DIR}/bin/Runner.Listener run" 2>/dev/null || true
  sleep 2
  cd "$RUNNER_DIR"
  nohup ./run.sh >> runner-console.log 2>&1 &
  echo "Runner restarted (PID $!)."
fi
