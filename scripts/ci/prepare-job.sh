#!/usr/bin/env bash
# Sync the lab repository to the triggering commit without logging local paths.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ci_cd_lab

resolve_ansible_playbook() {
  if [[ -x "${SWIM_LAB_ROOT}/.venv/bin/ansible-playbook" ]]; then
    printf '%s\n' "${SWIM_LAB_ROOT}/.venv/bin/ansible-playbook"
    return 0
  fi
  if command -v ansible-playbook >/dev/null 2>&1; then
    ci_log "NOTE: Using ansible-playbook from PATH (install into .venv for reproducible CI)."
    command -v ansible-playbook
    return 0
  fi
  ci_log "ERROR: ansible-playbook not found in .venv or PATH."
  ci_log "Complete Installation (README) before running CI."
  exit 1
}

for path in \
  ".vault_pass" \
  "ansible/inventory/group_vars/catalyst_center/vault.yml"; do
  if [[ ! -e "$path" ]]; then
    ci_log "ERROR: Missing lab file: ${path}"
    ci_log "Complete Installation (README) before running CI."
    exit 1
  fi
done

git fetch origin master
git checkout -f "${GITHUB_SHA}"

ANSIBLE_PLAYBOOK="$(resolve_ansible_playbook)"

{
  echo "ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK}"
  if [[ -d "${SWIM_LAB_ROOT}/.venv" ]]; then
    echo "VIRTUAL_ENV=${SWIM_LAB_ROOT}/.venv"
    echo "PATH=${SWIM_LAB_ROOT}/.venv/bin:${PATH}"
  fi
} >> "${GITHUB_ENV}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "start_epoch=$(date +%s)" >> "${GITHUB_OUTPUT}"
fi

ci_log "Lab repository synced to commit ${GITHUB_SHA:0:7}"
"${ANSIBLE_PLAYBOOK}" --version 2>&1 | ci_redact_stream | head -1
