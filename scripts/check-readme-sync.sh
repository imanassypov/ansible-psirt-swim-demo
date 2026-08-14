#!/usr/bin/env bash
# Fail when repository changes require README.md updates but README is stale.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
README="$REPO_ROOT/README.md"
PLAYBOOK_DIR="$REPO_ROOT/ansible/playbooks"
MODE="${1:-}"

if [[ ! -f "$README" ]]; then
  echo "ERROR: README.md not found at repo root." >&2
  exit 1
fi

errors=0

report_error() {
  echo "ERROR: $1" >&2
  errors=1
}

# Every tracked playbook must be referenced in README.md.
if [[ -d "$PLAYBOOK_DIR" ]]; then
  while IFS= read -r -d '' playbook; do
    name="$(basename "$playbook")"
    if ! grep -Fq "$name" "$README"; then
      report_error "README.md is missing a reference to playbook '$name'."
    fi
  done < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -print0 | sort -z)
fi

collect_changed_files() {
  if [[ "$MODE" == "--staged" ]]; then
    git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR
    return
  fi

  {
    git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR 2>/dev/null || true
    git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u
}

is_doc_trigger() {
  local file="$1"
  case "$file" in
    README.md|Settings/readme.md|.cursor/*|scripts/check-readme-sync.sh|.githooks/*)
      return 1
      ;;
    ansible/playbooks/*|ansible/roles/*|Settings/*|ansible/inventory/*|ansible/collections/*|requirements-ansible.txt|ansible/ansible.cfg|.cursor/rules/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

changed_files="$(collect_changed_files || true)"
if [[ -n "$changed_files" ]]; then
  readme_changed=false
  trigger_changed=false
  trigger_paths=()

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ "$file" == "README.md" ]]; then
      readme_changed=true
    fi
    if is_doc_trigger "$file"; then
      trigger_changed=true
      trigger_paths+=("$file")
    fi
  done <<< "$changed_files"

  if [[ "$trigger_changed" == true && "$readme_changed" == false ]]; then
    report_error "README.md must be updated when changing demo structure or behavior."
    echo "Triggering paths:" >&2
    printf '  - %s\n' "${trigger_paths[@]}" >&2
    echo "Update README.md sections such as playbook table, directory structure, run commands, and troubleshooting." >&2
  fi
fi

if [[ "$errors" -ne 0 ]]; then
  echo "Run './scripts/check-readme-sync.sh' after updating README.md." >&2
  exit 1
fi

echo "README sync check passed."
exit 0
