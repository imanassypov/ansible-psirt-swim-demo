#!/usr/bin/env bash
# Install and register a self-hosted GitHub Actions runner under .github/actions-runner/
# Usage:
#   ./scripts/setup-actions-runner.sh
#   ./scripts/setup-actions-runner.sh --start-service
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_DIR="$REPO_ROOT/.github/actions-runner"
RUNNER_VERSION="${RUNNER_VERSION:-2.336.0}"
REPO_URL="${REPO_URL:-https://github.com/imanassypov/ansible-psirt-swim-demo}"
RUNNER_NAME="${RUNNER_NAME:-swim-lab-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,swim-lab,macOS,arm64}"
INSTALL_SERVICE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-service) INSTALL_SERVICE=true; shift ;;
    --runner-name) RUNNER_NAME="$2"; shift 2 ;;
    --version) RUNNER_VERSION="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

arch="$(uname -m)"
case "$arch" in
  arm64) RUNNER_ARCH="arm64" ;;
  x86_64) RUNNER_ARCH="x64" ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

os="$(uname -s)"
case "$os" in
  Darwin) RUNNER_OS="osx" ;;
  Linux) RUNNER_OS="linux" ;;
  *) echo "Unsupported OS: $os" >&2; exit 1 ;;
esac

TARBALL="actions-runner-${RUNNER_OS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required. Install with: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ -x ./config.sh && -f ./run.sh ]]; then
  echo "Runner files already present in $RUNNER_DIR"
else
  echo "Downloading Actions runner v${RUNNER_VERSION} (${RUNNER_OS}-${RUNNER_ARCH})..."
  curl -fsSL -o "$TARBALL" "$DOWNLOAD_URL"
  tar xzf "$TARBALL"
  rm -f "$TARBALL"
fi

if [[ -f .runner ]]; then
  echo "Runner already configured (.runner exists). Skipping config.sh."
  echo "To re-register, remove $RUNNER_DIR and re-run this script."
else
  echo "Requesting registration token from GitHub..."
  REG_TOKEN="$(
    gh api "repos/imanassypov/ansible-psirt-swim-demo/actions/runners/registration-token" \
      -X POST --jq .token
  )"

  echo "Configuring runner as '${RUNNER_NAME}'..."
  ./config.sh \
    --url "$REPO_URL" \
    --token "$REG_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --unattended \
    --replace
fi

echo ""
echo "Runner installed at: $RUNNER_DIR"
echo ""

start_interactive() {
  echo "Starting runner in background (./run.sh)..."
  cd "$RUNNER_DIR"
  if pgrep -f "Runner.Listener" >/dev/null 2>&1; then
    echo "Runner process already running."
  else
    nohup ./run.sh > runner-console.log 2>&1 &
    echo "Started PID $! — logs: $RUNNER_DIR/runner-console.log"
  fi
  sleep 2
  gh api "repos/imanassypov/ansible-psirt-swim-demo/actions/runners" \
    --jq '.runners[] | select(.name=="'"$RUNNER_NAME"'") | {name, status}' || true
}

if [[ "$INSTALL_SERVICE" == true ]]; then
  if [[ "$os" == "Darwin" && "$REPO_ROOT" == "$HOME/Documents"* ]]; then
    echo "NOTE: macOS restricts launchd services from ~/Documents (Operation not permitted)."
    echo "      Using interactive background start instead of ./svc.sh."
    echo "      For a persistent service, move the repo outside Documents or grant"
    echo "      Full Disk Access to the runner in System Settings → Privacy."
    echo ""
    start_interactive
  else
    echo "Installing and starting launchd service..."
    ./svc.sh install
    ./svc.sh start
    ./svc.sh status || true
    echo ""
    echo "Runner service started. Verify in GitHub: Settings → Actions → Runners"
  fi
else
  echo "Start interactively (foreground):"
  echo "  cd \"$RUNNER_DIR\" && ./run.sh"
  echo ""
  echo "Start in background:"
  echo "  cd \"$RUNNER_DIR\" && nohup ./run.sh > runner-console.log 2>&1 &"
  echo ""
  echo "Or install as a launchd service (may fail under ~/Documents on macOS):"
  echo "  $0 --start-service"
fi
