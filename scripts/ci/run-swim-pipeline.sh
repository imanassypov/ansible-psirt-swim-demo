#!/usr/bin/env bash
# CI: run the full SWIM playbook sequence.
set -euo pipefail

cd ansible

echo "=== Stage 00.2 — pre-upgrade compliance ==="
ansible-playbook playbooks/00.2_swim_validate_compliance.yml

echo "=== Stage 01.1 — import and golden tag ==="
ansible-playbook playbooks/01.1_swim_import_and_tag.yml

echo "=== Stage 01.2 — distribute to flash ==="
ansible-playbook playbooks/01.2_swim_distribute.yml

echo "=== Stage 01.3 — activate (device reload) ==="
ansible-playbook playbooks/01.3_swim_activate.yml

echo "=== Stage 00.2 — post-activation compliance ==="
ansible-playbook playbooks/00.2_swim_validate_compliance.yml -e post_activate=true
