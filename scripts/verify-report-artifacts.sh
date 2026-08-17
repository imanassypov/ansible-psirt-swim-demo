#!/usr/bin/env bash
# Fail if report artifacts still contain local paths or customer/lab identifiers.
set -euo pipefail

REPORT_DIR="${1:-}"
if [[ -z "$REPORT_DIR" || ! -d "$REPORT_DIR" ]]; then
  echo "ERROR: report directory required." >&2
  echo "usage: $0 reports/<run-label>/" >&2
  exit 1
fi

FORBIDDEN_PATTERNS=(
  '/Users/'
  '/home/'
  'Documents/Speaking'
  'SWIM_LAB_ROOT'
  'Global/PODS'
  '198\.18\.'
  '198\.19\.'
  'catalystcenter_password'
  'ansible_password'
  'ansible_ssh_pass'
  'ansible_become_pass'
  '"password"[[:space:]]*:'
  '-----BEGIN'
)

violations=0
while IFS= read -r -d '' file; do
  for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if [[ "$pattern" == -----BEGIN* ]]; then
      if grep -Fq -- "$pattern" "$file"; then
        echo "ERROR: forbidden pattern '$pattern' in ${file#"${REPORT_DIR}/"}" >&2
        violations=$((violations + 1))
      fi
    elif grep -Eq -- "$pattern" "$file"; then
      echo "ERROR: forbidden pattern '$pattern' in ${file#"${REPORT_DIR}/"}" >&2
      violations=$((violations + 1))
    fi
  done
done < <(find "$REPORT_DIR" -type f \( -name '*.json' -o -name '*.md' \) -print0)

if [[ "$violations" -gt 0 ]]; then
  echo "ERROR: report sanitization check failed ($violations violation(s))." >&2
  exit 1
fi

echo "Report sanitization check passed for ${REPORT_DIR##*/}/"
