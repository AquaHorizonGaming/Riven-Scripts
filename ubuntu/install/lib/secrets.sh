#!/usr/bin/env bash

generate_secrets() {
  banner 'Secrets Generation'

  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  AUTH_SECRET="$(openssl rand -base64 32)"

  set +o pipefail
  BACKEND_API_KEY="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  set -o pipefail

  [[ "${#BACKEND_API_KEY}" -eq 32 ]] || fail "Invalid BACKEND_API_KEY generated (expected 32, got ${#BACKEND_API_KEY})"
  [[ "$BACKEND_API_KEY" =~ ^[A-Za-z0-9]{32}$ ]] || fail 'Invalid BACKEND_API_KEY generated (must be alphanumeric, 32 chars)'

  export POSTGRES_PASSWORD
  export AUTH_SECRET
  export BACKEND_API_KEY

  ok 'Secrets generated'
}
