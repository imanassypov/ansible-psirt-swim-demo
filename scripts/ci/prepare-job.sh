#!/usr/bin/env bash
# Sync the lab repository to the triggering commit without logging local paths.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

ci_cd_lab

for path in \
  ".venv/bin/ansible-playbook" \
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

{
  echo "VIRTUAL_ENV=${SWIM_LAB_ROOT}/.venv"
  echo "PATH=${SWIM_LAB_ROOT}/.venv/bin:${PATH}"
} >> "${GITHUB_ENV}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "start_epoch=$(date +%s)" >> "${GITHUB_OUTPUT}"
fi

ci_log "Lab repository synced to commit ${GITHUB_SHA:0:7}"
"${SWIM_LAB_ROOT}/.venv/bin/ansible-playbook" --version 2>&1 | ci_redact_stream | head -1
