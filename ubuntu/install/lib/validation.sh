#!/usr/bin/env bash

require_ubuntu() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    fail "This installer must be run on Ubuntu Linux. Detected: $(uname -s)"
  fi

  if grep -qi microsoft /proc/version 2>/dev/null; then
    warn "WSL detected — this is not recommended"
    read -rp "Continue anyway? [y/N]: " yn
    [[ "${yn:-}" =~ ^[Yy]$ ]] || exit 1
  fi

  if [[ ! -f /etc/os-release ]]; then
    fail "Cannot determine OS (missing /etc/os-release)"
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu required."
  fi

  ok "Ubuntu detected (${PRETTY_NAME})"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "Run with sudo"
}
