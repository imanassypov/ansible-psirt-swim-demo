#!/usr/bin/env bash
# Sync the lab repository to the triggering commit without logging local paths.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

if [[ "${SWIM_PREPARE_PHASE:-}" != "post-sync" ]]; then
  ci_cd_lab

  for path in \
    ".vault_pass" \
    "ansible/inventory/group_vars/catalyst_center/vault.yml"; do
    if [[ ! -e "$path" ]]; then
      ci_log "ERROR: Missing lab file: ${path}"
      ci_log "Complete Installation (README) before running CI."
      exit 1
    fi
  done

  git fetch -q origin master
  git checkout -q master
  git reset --hard "${GITHUB_SHA}"

  # CI helpers track origin/master so a settings.json commit at an older SHA
  # does not run a stale in-memory prepare script against a reset tree.
  # Unstage them so they never ride along in a later report commit.
  git checkout origin/master -- scripts/ci/
  git reset -q HEAD -- scripts/ci/

  export SWIM_PREPARE_PHASE=post-sync
  exec bash "${SWIM_LAB_ROOT}/scripts/ci/prepare-job.sh"
fi

ci_cd_lab
ci_activate_lab_env
if [[ -z "${ANSIBLE_PLAYBOOK:-}" ]]; then
  ci_log "ERROR: ansible-playbook not found in .venv or PATH."
  ci_log "Complete Installation (README) before running CI."
  exit 1
fi

if ! python -c "import catalystcentersdk" 2>/dev/null; then
  ci_log "ERROR: catalystcentersdk is not installed in .venv."
  ci_log "Run: pip install -r requirements-ansible.txt"
  exit 1
fi

bash "${SCRIPT_DIR}/check-lab-connectivity.sh"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "start_epoch=$(date +%s)" >> "${GITHUB_OUTPUT}"
fi

ci_log "Lab repository synced to commit ${GITHUB_SHA:0:7}"
ansible_version="$("${ANSIBLE_PLAYBOOK}" --version 2>&1 || true)"
ci_log "${ansible_version%%$'\n'*}"
