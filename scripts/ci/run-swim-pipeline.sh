#!/usr/bin/env bash
# Run the SWIM playbook sequence from the lab repository (paths redacted in logs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ci_cd_lab
ci_activate_lab_env
cd ansible

if [[ -z "${ANSIBLE_PLAYBOOK:-}" ]]; then
  ci_log "ERROR: ansible-playbook not found (run Prepare lab job first)."
  exit 1
fi

_run_playbook() {
  local label="$1"
  shift
  ci_log "=== ${label} ==="
  "${ANSIBLE_PLAYBOOK}" "$@" 2>&1 | ci_redact_stream
}

_run_playbook "Stage 00.2 — pre-upgrade compliance" \
  playbooks/00.2_swim_validate_compliance.yml

_run_playbook "Stage 01.1 — import and golden tag" \
  playbooks/01.1_swim_import_and_tag.yml

_run_playbook "Stage 01.2 — distribute to flash" \
  playbooks/01.2_swim_distribute.yml

_run_playbook "Stage 01.3 — activate (device reload)" \
  playbooks/01.3_swim_activate.yml

_run_playbook "Stage 00.2 — post-activation compliance" \
  playbooks/00.2_swim_validate_compliance.yml -e post_activate=true
