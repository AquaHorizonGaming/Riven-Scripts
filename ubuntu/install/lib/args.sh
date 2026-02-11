#!/usr/bin/env bash

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        cat <<'USAGE'
Usage: install.sh
  --help, -h    Show this help
USAGE
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}
