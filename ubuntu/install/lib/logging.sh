#!/usr/bin/env bash

banner() {
  echo -e "\n========================================\n $1\n========================================"
}

ok() {
  printf '✔  %s\n' "$1"
}

warn() {
  printf '⚠  %s\n' "$1"
}

fail() {
  printf '✖  %s\n' "$1" >&2
  exit 1
}

init_logging() {
  local log_dir="$1"

  LOG_FILE="$log_dir/install-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$log_dir"
  touch "$LOG_FILE"

  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'fail "Installer exited unexpectedly at line $LINENO"' ERR

  ok "Logging initialized: $LOG_FILE"
}
