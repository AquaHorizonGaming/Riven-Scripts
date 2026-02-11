#!/usr/bin/env bash

detect_uid_gid() {
  banner 'UserDetect'

  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != 'root' ]]; then
    TARGET_USER="$SUDO_USER"
    TARGET_UID="$(id -u "$SUDO_USER")"
    TARGET_GID="$(id -g "$SUDO_USER")"
    ok "Detected sudo user ownership: UID=$TARGET_UID GID=$TARGET_GID"
    return
  fi

  TARGET_USER="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"

  if [[ -n "$TARGET_USER" ]]; then
    TARGET_UID="$(id -u "$TARGET_USER")"
    TARGET_GID="$(id -g "$TARGET_USER")"
    ok "Detected user ownership: UID=$TARGET_UID GID=$TARGET_GID"
    return
  fi

  TARGET_USER=''
  TARGET_UID=1000
  TARGET_GID=1000
  warn 'No non-root user detected; defaulting ownership to UID=1000 GID=1000'
}
