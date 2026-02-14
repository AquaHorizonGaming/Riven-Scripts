#!/usr/bin/env bash

select_seer_install() {
  banner 'Seer Selection'

  echo 'Would you like to install Seer (request manager)?'
  echo '1) Yes'
  echo '2) No'
  read -r -p 'Select ONE: ' SEER_SEL

  case "$SEER_SEL" in
    1)
      INSTALL_SEER='true'
      echo
      echo 'Enter your Seer API key to inject into the environment configuration.'
      SEER_API_KEY="$(require_non_empty 'Enter Seer API Key')"
      ;;
    2)
      INSTALL_SEER='false'
      SEER_API_KEY=''
      ;;
    *) fail 'Seer selection is required' ;;
  esac
}

setup_seer() {
  banner 'Seer Setup'

  [[ -n "${SEER_API_KEY:-}" ]] || fail 'SEER_API_KEY is missing from environment configuration'

  cd "$INSTALL_DIR"
  docker compose up -d seer

  SERVER_IP="$(hostname -I | awk '{print $1}')"

  cat <<EOF_SEER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SEER INSTALLED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Seer is now running.

Access it at:

    http://$SERVER_IP:5055

Seer API Key:

    $SEER_API_KEY

The API key has been injected into your existing environment configuration.

Next steps:

1) Open Seer UI
2) Complete setup wizard
3) Use the API key above if required for integrations

IMPORTANT:
Riven does NOT use Sonarr or Radarr in this setup.
You may ignore those sections inside Seer.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF_SEER
}
