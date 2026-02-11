#!/usr/bin/env bash

trim_whitespace() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

sanitize() {
  printf '%s' "$1" | tr -d '\r\n'
}

is_non_empty() {
  [[ -n "$(trim_whitespace "${1:-}")" ]]
}

is_url() {
  [[ "${1:-}" =~ ^https?:// ]]
}

require_non_empty() {
  local prompt="$1"
  local val=""

  while true; do
    IFS= read -r -p "$prompt: " val
    val="$(trim_whitespace "$(sanitize "$val")")"
    is_non_empty "$val" && {
      printf '%s' "$val"
      return
    }
    warn "Value required"
  done
}

read_masked_non_empty() {
  local prompt="$1"
  local val=""
  local char=""

  while true; do
    val=""
    printf '%s: ' "$prompt"

    while IFS= read -r -s -n1 char; do
      [[ "$char" == $'\n' ]] && break
      if [[ "$char" == $'\177' ]]; then
        if [[ -n "$val" ]]; then
          val="${val%?}"
          printf '\b \b'
        fi
        continue
      fi
      val+="$char"
      printf '*'
    done

    echo
    val="$(trim_whitespace "$val")"
    is_non_empty "$val" && {
      printf '%s' "$val"
      return
    }
    warn "Value required"
  done
}

require_url() {
  local prompt="$1"
  local val=""

  while true; do
    IFS= read -r -p "$prompt: " val
    val="$(trim_whitespace "$(sanitize "$val")")"
    is_url "$val" && {
      printf '%s' "$val"
      return
    }
    warn 'Must include http:// or https://'
  done
}
