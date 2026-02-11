#!/usr/bin/env bash

banner(){ echo -e "\n========================================\n $1\n========================================"; }
ok()   { printf "✔  %s\n" "$1"; }
warn() { printf "⚠  %s\n" "$1"; }
fail() { printf "✖  %s\n" "$1"; exit 1; }

require_non_empty() {
  local prompt="$1" val
  while true; do
    IFS= read -r -p "$prompt: " val
    val="$(printf '%s' "$val" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    warn "Value required"
  done
}

read_masked_non_empty() {
  local prompt="$1"
  local val="" char

  while true; do
    val=""
    printf "%s: " "$prompt"

    while IFS= read -r -s -n1 char; do
      [[ $char == $'\n' ]] && break

      if [[ $char == $'\177' ]]; then
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

    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    warn "Value required"
  done
}

require_url() {
  local prompt="$1" val
  while true; do
    IFS= read -r -p "$prompt: " val
    val="$(printf '%s' "$val" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ "$val" =~ ^https?:// ]] && { printf '%s' "$val"; return; }
    warn "Must include http:// or https://" >&2
  done
}

sanitize() {
  printf "%s" "$1" | tr -d '\r\n'
}
