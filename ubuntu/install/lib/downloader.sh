#!/usr/bin/env bash

select_downloader() {
  banner 'Downloader Selection (REQUIRED)'

  echo '• API keys entered below will be masked for security.'
  echo
  echo 'Choose ONE downloader service:'
  echo
  echo '1) Real-Debrid'
  echo '2) All-Debrid'
  echo '3) Debrid-Link'
  echo

  read -r -p 'Select ONE: ' DL_SEL

  RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=false
  RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=false
  RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=false

  RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=''
  RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=''
  RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=''

  case "$DL_SEL" in
    1)
      RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=true
      echo
      echo 'Real-Debrid API Token required.'
      echo
      echo 'How to get it:'
      echo '  1) Visit https://real-debrid.com/apitoken'
      echo '  2) Copy the API Token shown'
      echo
      echo 'Paste ONLY the API token value below:'
      RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY="$(require_non_empty 'Enter Real-Debrid API Token')"
      ;;
    2)
      RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=true
      echo
      echo 'All-Debrid API Key required.'
      echo
      echo 'How to get it:'
      echo '  1) Visit https://alldebrid.com/apikeys'
      echo '  2) Generate or copy an existing key'
      echo
      echo 'Paste ONLY the API key value below:'
      RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY="$(require_non_empty 'Enter All-Debrid API Key')"
      ;;
    3)
      RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=true
      echo
      echo 'Debrid-Link API Key required.'
      echo
      echo 'How to get it:'
      echo '  1) Visit https://debrid-link.com/webapp/apikey'
      echo '  2) Copy your API key'
      echo
      echo 'Paste ONLY the API key value below:'
      RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY="$(require_non_empty 'Enter Debrid-Link API Key')"
      ;;
    *)
      fail 'Downloader selection REQUIRED'
      ;;
  esac
}
