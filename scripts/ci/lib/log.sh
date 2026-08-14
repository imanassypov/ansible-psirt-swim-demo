#!/usr/bin/env bash
# Redact local filesystem paths from CI log output.
# Source from scripts under scripts/ci/ — never echo raw SWIM_LAB_ROOT in logs.

_swim_ci_redact() {
  local text="${1-}"
  [[ -z "$text" ]] && return 0

  if [[ -n "${SWIM_LAB_ROOT:-}" ]]; then
    text="${text//${SWIM_LAB_ROOT}/<lab-root>}"
  fi
  if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    text="${text//${GITHUB_WORKSPACE}/<workspace>}"
  fi
  if [[ -n "${HOME:-}" ]]; then
    text="${text//${HOME}/<home>}"
  fi
  if [[ -n "${RUNNER_ROOT:-}" ]]; then
    text="${text//${RUNNER_ROOT}/<runner-root>}"
  fi

  # Catch-all: macOS home paths and usernames in path segments.
  text="$(printf '%s' "$text" | sed -E \
    -e 's#/Users/[^/[:space:]]+#<home>#g' \
    -e 's#/private/var/[^/[:space:]]+#<system-var>#g' \
    -e 's#Speaking Sessions/Secure Networking Webinar[^[:space:]]*#<lab-root>#g')"

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

# Pipe-friendly filter for command output (e.g. ansible-playbook).
ci_redact_stream() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    ci_log "$line"
  done
}
