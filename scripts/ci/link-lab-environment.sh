#!/usr/bin/env bash
# CI: link gitignored lab files (.venv, vault) into the Actions job workspace.
set -euo pipefail

if [[ -z "${SWIM_LAB_ROOT:-}" ]]; then
  echo "SWIM_LAB_ROOT is not set on the runner." >&2
  echo "Run from the repository root: ./scripts/fix-runner-workdir.sh --restart" >&2
  exit 1
fi

LAB_ROOT="$(cd "${SWIM_LAB_ROOT}" && pwd)"

echo "Lab root: ${LAB_ROOT}"
echo "Job workspace: ${GITHUB_WORKSPACE}"

missing=0
for path in \
  ".venv/bin/ansible-playbook" \
  ".vault_pass" \
  "ansible/inventory/group_vars/catalyst_center/vault.yml"; do
  if [[ ! -e "${LAB_ROOT}/${path}" ]]; then
    echo "Missing lab file: ${path}" >&2
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  echo "Install the lab environment first (see README Installation)." >&2
  exit 1
fi

ln -sfn "${LAB_ROOT}/.venv" .venv
ln -sfn "${LAB_ROOT}/.vault_pass" .vault_pass
mkdir -p ansible/inventory/group_vars/catalyst_center
ln -sfn "${LAB_ROOT}/ansible/inventory/group_vars/catalyst_center/vault.yml" \
  ansible/inventory/group_vars/catalyst_center/vault.yml

{
  echo "LAB_ROOT=${LAB_ROOT}"
  echo "VIRTUAL_ENV=${LAB_ROOT}/.venv"
  echo "PATH=${LAB_ROOT}/.venv/bin:${PATH}"
} >> "${GITHUB_ENV}"

"${LAB_ROOT}/.venv/bin/ansible-playbook" --version
"${LAB_ROOT}/.venv/bin/ansible-galaxy" collection list cisco.catalystcenter 2>/dev/null | head -3 || true
