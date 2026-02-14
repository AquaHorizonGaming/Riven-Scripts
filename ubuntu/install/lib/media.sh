#!/usr/bin/env bash

select_media_server() {
  banner 'Media Server Selection (REQUIRED)'

  echo '1) Plex (Install)'
  echo '2) Emby (Install)'
  echo '3) Jellyfin (Install)'
  echo '4) I already have a media server'
  read -r -p 'Select media server: ' MEDIA_SEL

  case "$MEDIA_SEL" in
    1) MEDIA_SERVER='managed'; MEDIA_PROFILE='plex'; MEDIA_PORT=32400 ;;
    2) MEDIA_SERVER='managed'; MEDIA_PROFILE='emby'; MEDIA_PORT=8097 ;;
    3) MEDIA_SERVER='managed'; MEDIA_PROFILE='jellyfin'; MEDIA_PORT=8096 ;;
    4)
      MEDIA_SERVER='external'
      MEDIA_PROFILE='external'
      MEDIA_PORT=''
      select_external_media_server
      ;;
    *) fail 'Media server selection is required' ;;
  esac
}

select_external_media_server() {
  echo
  echo 'Which media server are you currently running?'
  echo
  echo '1) Plex'
  echo '2) Emby'
  echo '3) Jellyfin'
  read -r -p 'Select ONE media server: ' EXTERNAL_MEDIA_SEL

  case "$EXTERNAL_MEDIA_SEL" in
    1) EXTERNAL_MEDIA_TYPE='plex' ;;
    2) EXTERNAL_MEDIA_TYPE='emby' ;;
    3) EXTERNAL_MEDIA_TYPE='jellyfin' ;;
    *) fail 'External media server selection is required' ;;
  esac
}

collect_media_auth() {
  if [[ "${MEDIA_SERVER:-managed}" == 'external' ]]; then
    banner 'Media Server Authentication'
    echo 'Using existing media server; authentication will be configured in Riven after install.'
    return
  fi

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

print_jellyfin_external() {
  cat <<'EOF_JELLYFIN'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
JELLYFIN CONFIGURATION REQUIRED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You selected: Existing Jellyfin Server

1) In your existing Jellyfin server:
   - Go to Dashboard → API Keys
   - Create a new API key
   - Name it: riven

2) Copy the generated API key.

3) Paste it into your Riven configuration
   where prompted for the Jellyfin API key.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT: LIBRARY PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Riven mounts media to:

    /mnt/riven/mount

You MUST:

• Add /mnt/riven/mount as a library path in Jellyfin
• OR if running in Docker, add this volume mapping:

    - /mnt/riven/mount:/media

Then rescan your Jellyfin libraries.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF_JELLYFIN
}

print_emby_external() {
  cat <<'EOF_EMBY'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EMBY CONFIGURATION REQUIRED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1) Open your Emby Dashboard
2) Go to Advanced → API Keys
3) Create a new key
4) Name it: riven
5) Copy the API key

Paste this key into your Riven configuration.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT: LIBRARY PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Riven mounts media to:

    /mnt/riven/mount

You MUST:

• Add /mnt/riven/mount as a library folder
• OR if using Docker, map:

    - /mnt/riven/mount:/media

Then refresh your libraries.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF_EMBY
}

print_plex_external() {
  cat <<'EOF_PLEX'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PLEX CONFIGURATION REQUIRED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Riven requires your Plex Token.

1) Open Plex Web
2) Visit: http://YOUR_PLEX_IP:32400/web
3) Retrieve your Plex token
   (Use Plex token retrieval method already defined in script)

Paste your Plex token into the Riven configuration.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT: LIBRARY PATH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Riven mounts media to:

    /mnt/riven/mount

You MUST:

• Add /mnt/riven/mount as a library location in Plex
• OR if running Plex in Docker, map:

    - /mnt/riven/mount:/media

Then rescan libraries.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF_PLEX
}

print_external_media_instructions() {
  banner 'EXISTING MEDIA SERVER SETUP'

  case "$EXTERNAL_MEDIA_TYPE" in
    jellyfin) print_jellyfin_external ;;
    emby) print_emby_external ;;
    plex) print_plex_external ;;
  esac
}

configure_origin() {
  banner 'Frontend Origin'

  ORIGIN="$DEFAULT_ORIGIN"
  read -r -p 'Using reverse proxy? (y/N): ' USE_PROXY
  [[ "${USE_PROXY,,}" == 'y' ]] && ORIGIN="$(require_url 'Public frontend URL')"
  ok "ORIGIN=$ORIGIN"
}
