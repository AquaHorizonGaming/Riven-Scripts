#!/usr/bin/env bash

select_media_server() {
  banner 'Media Server Selection (REQUIRED)'

  echo '1) Jellyfin'
  echo '2) Plex'
  echo '3) Emby'
  read -r -p 'Select ONE media server: ' MEDIA_SEL

  case "$MEDIA_SEL" in
    1) MEDIA_PROFILE='jellyfin'; MEDIA_PORT=8096 ;;
    2) MEDIA_PROFILE='plex'; MEDIA_PORT=32400 ;;
    3) MEDIA_PROFILE='emby'; MEDIA_PORT=8097 ;;
    *) fail 'Media server REQUIRED' ;;
  esac
}

collect_media_auth() {
  banner 'Media Server Authentication'

  echo '⚠️  Note:'
  echo '  • When pasting keys/tokens below, the input will NOT be visible.'
  echo '  • This is intentional for security.'
  echo '  • Paste normally and press ENTER.'
  echo

  case "$MEDIA_PROFILE" in
    jellyfin)
      echo 'Jellyfin requires an API key.'
      echo
      echo 'How to get it:'
      echo '  1) Open Jellyfin Web UI'
      echo '  2) Dashboard → API Keys'
      echo '  3) Create a new API key'
      echo
      echo 'Paste ONLY the API key value below:'
      MEDIA_API_KEY="$(require_non_empty 'Enter Jellyfin API Key')"
      ;;
    plex)
      echo 'Plex requires a USER TOKEN (NOT an API key).'
      echo
      echo 'How to get it:'
      echo '  1) Open Plex Web App and ensure you are logged in'
      echo '  2) Visit: https://plex.tv/devices.xml'
      echo '  3) Copy the value of X-Plex-Token'
      echo
      echo '⚠️  IMPORTANT:'
      echo "  • Paste ONLY the token value"
      echo "  • Do NOT include 'token='"
      echo '  • Do NOT paste XML or URLs'
      echo
      echo 'Paste the token below:'
      MEDIA_API_KEY="$(require_non_empty 'Enter Plex X-Plex-Token')"
      ;;
    emby)
      echo 'Emby requires an API key.'
      echo
      echo 'How to get it:'
      echo '  1) Open Emby Web UI'
      echo '  2) Settings → Advanced → API Keys'
      echo '  3) Create a new API key'
      echo
      echo 'Paste ONLY the API key value below:'
      MEDIA_API_KEY="$(require_non_empty 'Enter Emby API Key')"
      ;;
  esac
}

configure_origin() {
  banner 'Frontend Origin'

  ORIGIN="$DEFAULT_ORIGIN"
  read -r -p 'Using reverse proxy? (y/N): ' USE_PROXY
  [[ "${USE_PROXY,,}" == 'y' ]] && ORIGIN="$(require_url 'Public frontend URL')"
  ok "ORIGIN=$ORIGIN"
}
