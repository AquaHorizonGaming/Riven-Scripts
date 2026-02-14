#!/usr/bin/env bash

select_seerr_install() {
  banner 'Seerr Selection'

  echo 'Would you like to install Seerr (request manager)?'
  echo '1) Yes'
  echo '2) No'
  read -r -p 'Select ONE: ' SEERR_SEL

  case "$SEERR_SEL" in
    1)
      INSTALL_SEERR='true'
      echo
      echo 'Enter your Seerr API key to inject into the environment configuration.'
      SEERR_API_KEY="$(require_non_empty 'Enter Seerr API Key')"
      ;;
    2)
      INSTALL_SEERR='false'
      SEERR_API_KEY=''
      ;;
    *) fail 'Seerr selection is required' ;;
  esac
}

setup_seerr() {
  banner 'Seerr Setup'

  [[ -n "${SEERR_API_KEY:-}" ]] || fail 'SEERR_API_KEY is missing from environment configuration'

  cd "$INSTALL_DIR"
  docker compose up -d seerr

  SERVER_IP="$(hostname -I | awk '{print $1}')"

  cat <<EOF_SEERR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SEERR INSTALLED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Seerr is now running.

Access it at:

    http://$SERVER_IP:5055

Seerr API Key:

    $SEERR_API_KEY

The API key has been injected into your existing environment configuration.

Next steps:

1) Open Seerr UI
2) Complete setup wizard
3) Use the API key above if required for integrations

IMPORTANT:
Riven does NOT use Sonarr or Radarr in this setup.
You may ignore those sections inside Seerr.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF_SEERR
}
