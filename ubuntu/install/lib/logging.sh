#!/usr/bin/env bash

log()        { echo "[INFO]  $*"; }
log_warn()   { echo "[WARN]  $*"; }
log_error()  { echo "[ERROR] $*"; }
log_section(){ echo -e "\n========== $* ==========\n"; }

init_logging() {
  local log_dir="$1"

  LOG_FILE="$log_dir/install-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$log_dir"
  touch "$LOG_FILE"

  exec > >(tee -a "$LOG_FILE") 2>&1
  trap 'log_error "Installer exited unexpectedly at line $LINENO"' ERR

  log "Logging initialized"
  log "Log file: $LOG_FILE"
}
