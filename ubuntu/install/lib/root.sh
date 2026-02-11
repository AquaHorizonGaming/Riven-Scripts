#!/usr/bin/env bash

require_root() {
  banner "Root Check"
  [[ "$(id -u)" -eq 0 ]] || fail 'Run with sudo or as root'
  ok 'Running as root'
}

require_ubuntu() {
  banner 'OS Check'

  if [[ "$(uname -s)" != 'Linux' ]]; then
    fail "This installer must be run on Ubuntu Linux. Detected: $(uname -s)"
  fi

  if grep -qi microsoft /proc/version 2>/dev/null; then
    warn 'WSL detected — this is not recommended'
    read -r -p 'Continue anyway? [y/N]: ' yn
    [[ "${yn:-}" =~ ^[Yy]$ ]] || exit 1
  fi

  [[ -f /etc/os-release ]] || fail 'Cannot determine OS (missing /etc/os-release)'
  # shellcheck disable=SC1091
  . /etc/os-release

  [[ "${ID:-}" == 'ubuntu' ]] || fail "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu required."
  ok "Ubuntu detected (${PRETTY_NAME})"
}
