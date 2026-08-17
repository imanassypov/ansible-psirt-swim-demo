#!/usr/bin/env bash
# Fail fast when the runner cannot reach Catalyst Center (e.g. lab VPN down).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ci_cd_lab

CONN_FILE="ansible/inventory/group_vars/catalyst_center/connection.yml"
if [[ ! -f "$CONN_FILE" ]]; then
  ci_log "ERROR: Missing Catalyst Center connection file: ${CONN_FILE}"
  exit 1
fi

read_connection_value() {
  local key="$1"
  grep -E "^${key}:" "$CONN_FILE" \
    | sed -E "s/^${key}:[[:space:]]*//" \
    | tr -d "\"'"
}

CATC_HOST="$(read_connection_value catalystcenter_host)"
CATC_PORT="$(read_connection_value catalystcenter_port)"
CATC_PORT="${CATC_PORT:-443}"

if [[ -z "$CATC_HOST" ]]; then
  ci_log "ERROR: catalystcenter_host is not set in ${CONN_FILE}"
  exit 1
fi

CONNECT_TIMEOUT="${CATC_CONNECT_TIMEOUT:-10}"

if python - "$CATC_HOST" "$CATC_PORT" "$CONNECT_TIMEOUT" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
timeout = float(sys.argv[3])

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(timeout)
try:
    sock.connect((host, port))
except OSError as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(1)
finally:
    sock.close()
PY
then
  ci_log "Catalyst Center reachable at ${CATC_HOST}:${CATC_PORT} (TCP)."
  exit 0
fi

ci_log "ERROR: Cannot reach Catalyst Center at ${CATC_HOST}:${CATC_PORT} (TCP)."
ci_log "Connect lab VPN on the self-hosted runner host and confirm routing to the lab network."
ci_log "Quick check: nc -zv ${CATC_HOST} ${CATC_PORT}"
exit 1
