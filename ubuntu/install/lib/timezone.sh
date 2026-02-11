#!/usr/bin/env bash

detect_timezone() {
  timedatectl show --property=Timezone --value 2>/dev/null \
    || cat /etc/timezone 2>/dev/null \
    || echo UTC
}

configure_timezone() {
  local detected input selected

  detected="$(detect_timezone)"
  read -rp "Timezone [$detected]: " input
  selected="${input:-$detected}"

  if [[ ! -f "/usr/share/zoneinfo/$selected" ]]; then
    fail "Invalid timezone: $selected"
  fi

  ln -sf "/usr/share/zoneinfo/$selected" /etc/localtime
  echo "$selected" > /etc/timezone

  TZ_SELECTED="$selected"
  ok "Timezone set: $TZ_SELECTED"
}
