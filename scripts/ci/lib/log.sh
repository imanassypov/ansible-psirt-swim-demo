#!/usr/bin/env bash
# Redact local filesystem paths from CI log output.
# Source from scripts under scripts/ci/ — never echo raw SWIM_LAB_ROOT in logs.

_swim_ci_redact() {
  local text="${1-}"
  [[ -z "$text" ]] && return 0

  # Longest/literal paths first.
  if [[ -n "${SWIM_LAB_ROOT:-}" ]]; then
    text="${text//${SWIM_LAB_ROOT}/<lab-root>}"
  fi
  if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    text="${text//${GITHUB_WORKSPACE}/<workspace>}"
  fi
  if [[ -n "${RUNNER_ROOT:-}" ]]; then
    text="${text//${RUNNER_ROOT}/<runner-root>}"
  fi
  if [[ -n "${HOME:-}" ]]; then
    text="${text//${HOME}/<home>}"
  fi

  # Fallback for any remaining absolute home paths.
  text="$(printf '%s' "$text" | sed -E 's#/Users/[^/[:space:]]+#<home>#g')"

  printf '%s' "$text"
}

ci_log() {
  _swim_ci_redact "$*"
  printf '\n'
}

ci_require_lab_root() {
  if [[ -z "${SWIM_LAB_ROOT:-}" || ! -d "${SWIM_LAB_ROOT}" ]]; then
    ci_log "ERROR: SWIM_LAB_ROOT is not configured on this runner."
    ci_log "Run from the repository: ./scripts/fix-runner-workdir.sh --restart"
    exit 1
  fi
}

ci_cd_lab() {
  ci_require_lab_root
  cd "${SWIM_LAB_ROOT}"
}

ci_activate_lab_env() {
  ci_require_lab_root
  if [[ -d "${SWIM_LAB_ROOT}/.venv" ]]; then
    export VIRTUAL_ENV="${SWIM_LAB_ROOT}/.venv"
    export PATH="${SWIM_LAB_ROOT}/.venv/bin:${PATH}"
  fi
  if [[ -z "${ANSIBLE_PLAYBOOK:-}" ]]; then
    if [[ -x "${SWIM_LAB_ROOT}/.venv/bin/ansible-playbook" ]]; then
      export ANSIBLE_PLAYBOOK="${SWIM_LAB_ROOT}/.venv/bin/ansible-playbook"
    elif command -v ansible-playbook >/dev/null 2>&1; then
      export ANSIBLE_PLAYBOOK="$(command -v ansible-playbook)"
    fi
  fi
}

# Pipe-friendly filter for command output (e.g. ansible-playbook).
ci_redact_stream() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    ci_log "$line"
  done
}
