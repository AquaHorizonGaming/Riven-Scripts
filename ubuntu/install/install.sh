#!/usr/bin/env bash
set -euo pipefail

TMP_ROOT="/tmp/riven-install"
TMP_DIR=""

fatal() {
  printf '✖  %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

resolve_base_url() {
  local default_owner="AquaHorizonGaming"
  local default_repo="riven-scripts"
  local default_branch="fix-install-script"
  local default_path="ubuntu/install"

  if [[ -n "${RIVEN_INSTALL_BASE_URL:-}" ]]; then
    printf '%s' "$RIVEN_INSTALL_BASE_URL"
    return
  fi

  if [[ -n "${INSTALL_BASE_URL:-}" ]]; then
    printf '%s' "$INSTALL_BASE_URL"
    return
  fi

  printf '%s' "https://raw.githubusercontent.com/${default_owner}/${default_repo}/${default_branch}/${default_path}"
}


ensure_module_endpoint_reachable() {
  local base_url="$1"
  local probe_url="$base_url/lib/helpers.sh"

  curl -fsSL "$probe_url" -o /dev/null \
    || fatal "Installer module endpoint is unreachable: $probe_url"
}

validate_downloaded_module() {
  local file="$1"

  [[ -s "$file" ]] || fatal "Downloaded module is empty: $(basename "$file")"
  bash -n "$file" || fatal "Downloaded module failed syntax check: $(basename "$file")"
}

download_module() {
  local base_url="$1"
  local module="$2"
  local destination="$TMP_DIR/lib/$module"

  curl -fsSL "$base_url/lib/$module" -o "$destination" \
    || fatal "Failed to download module: $module from $base_url/lib/$module"

  validate_downloaded_module "$destination"
}

source_module() {
  local file="$1"
  # shellcheck disable=SC1090
  source "$file" || fatal "Failed to load module: $(basename "$file")"
}

bootstrap_modules() {
  local base_url="$1"
  local modules=(
    "helpers.sh"
    "config.sh"
    "logging.sh"
    "validation.sh"
    "timezone.sh"
    "docker.sh"
  )

  mkdir -p "$TMP_ROOT"
  TMP_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"
  mkdir -p "$TMP_DIR/lib"

  ensure_module_endpoint_reachable "$base_url"

  for module in "${modules[@]}"; do
    download_module "$base_url" "$module"
  done

  source_module "$TMP_DIR/lib/helpers.sh"
  source_module "$TMP_DIR/lib/config.sh"
  source_module "$TMP_DIR/lib/logging.sh"
  source_module "$TMP_DIR/lib/validation.sh"
  source_module "$TMP_DIR/lib/timezone.sh"
  source_module "$TMP_DIR/lib/docker.sh"
}

BASE_URL="$(resolve_base_url)"
bootstrap_modules "$BASE_URL"

############################################
# OS CHECK (Ubuntu only, WSL warned)
############################################
banner "OS Check"
require_ubuntu

############################################
# ROOT CHECK
############################################
require_root

############################################
# INSTALLER VERSION
############################################
banner "Version"
print_installer_version

############################################
# LOGGING MODULE
############################################
banner "Logging"
init_logging "$LOG_DIR"

############################################
# TIMEZONE
############################################
banner "Timezone"
configure_timezone

############################################
# SYSTEM DEPS
############################################
banner "System Dependencies"

dpkg -s ca-certificates curl gnupg lsb-release openssl fuse3 >/dev/null 2>&1 \
  && ok "System dependencies already installed" \
  || {
    apt-get update || fail "apt update failed"
    apt-get install -y ca-certificates curl gnupg lsb-release openssl fuse3 \
      || fail "dependency install failed"
    ok "System dependencies installed"
  }

############################################
# USER / UID / GID DETECTION
############################################
banner "UserDetect"

detect_uid_gid() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    TARGET_UID="$(id -u "$SUDO_USER")"
    TARGET_GID="$(id -g "$SUDO_USER")"
    return
  fi

  local user
  user="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"

  if [[ -n "$user" ]]; then
    TARGET_UID="$(id -u "$user")"
    TARGET_GID="$(id -g "$user")"
    return
  fi

  TARGET_UID=1000
  TARGET_GID=1000
}

detect_uid_gid
ok "Detected user ownership: UID=$TARGET_UID GID=$TARGET_GID"

############################################
# DOCKER
############################################
banner "Docker"
ensure_docker_installed

############################################
# DOCKER GROUP / USER PERMISSIONS
############################################
banner "DockerGroup"
setup_docker_group

############################################
# FILESYSTEM
############################################
banner "Filesystem"

mkdir -p "$BACKEND_PATH" "$MOUNT_PATH" "$INSTALL_DIR"

chown "$TARGET_UID:$TARGET_GID" "$BACKEND_PATH" "$MOUNT_PATH" \
  || fail "Failed to chown backend or mount path"

chown "$TARGET_UID:$TARGET_GID" "$INSTALL_DIR" \
  || fail "Failed to chown install dir"

ok "Filesystem ready (owner: $TARGET_UID:$TARGET_GID)"

############################################
# RIVEN rshared MOUNT MODULE (REQUIRED)
############################################
ensure_riven_rshared_mount() {
  local mount_path="$MOUNT_PATH"
  local service_name="riven-bind-shared.service"

  banner "Ensuring rshared mount for Riven"

  mkdir -p "$mount_path"

  if findmnt -no PROPAGATION "$mount_path" 2>/dev/null | grep -q shared; then
    ok "Mount already rshared"
    return
  fi

  warn "Mount is not rshared — installing systemd unit"

  cat >"/etc/systemd/system/$service_name" <<EOF_SYSTEMD
[Unit]
Description=Make Riven mount bind shared
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --bind $mount_path $mount_path
ExecStart=/usr/bin/mount --make-rshared $mount_path
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now "$service_name"

  if findmnt -no PROPAGATION "$mount_path" | grep -q shared; then
    ok "rshared mount enforced"
  else
    fail "Failed to enforce rshared mount on $mount_path"
  fi
}

ensure_riven_rshared_mount
banner "Mounted $MOUNT_PATH"

############################################
# DOWNLOAD COMPOSE FILES
############################################
banner "Docker Compose Files"
cd "$INSTALL_DIR"
curl -fsSL "$MEDIA_COMPOSE_URL" -o docker-compose.media.yml
curl -fsSL "$RIVEN_COMPOSE_URL" -o docker-compose.yml
ok "Compose files downloaded"

############################################
# MEDIA SERVER SELECTION (REQUIRED)
############################################
banner "Media Server Selection (REQUIRED)"
echo "1) Jellyfin"
echo "2) Plex"
echo "3) Emby"
read -rp "Select ONE media server: " MEDIA_SEL

case "$MEDIA_SEL" in
  1) MEDIA_PROFILE="jellyfin"; MEDIA_PORT=8096 ;;
  2) MEDIA_PROFILE="plex";     MEDIA_PORT=32400 ;;
  3) MEDIA_PROFILE="emby";     MEDIA_PORT=8097 ;;
  *) fail "Media server REQUIRED" ;;
esac

banner "Starting Media Server"
docker compose -f docker-compose.media.yml --profile "$MEDIA_PROFILE" up -d
ok "Media server started"

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "➡️  Open your media server in a browser:"
echo "👉  http://$SERVER_IP:$MEDIA_PORT"
echo
echo "• Complete setup"
echo "• Create admin user"
echo "• Generate API key / token"
echo
read -rp "Press ENTER once media server setup is complete..."

banner "Media Server Authentication"

echo "⚠️  Note:"
echo "  • When pasting keys/tokens below, the input will NOT be visible."
echo "  • This is intentional for security."
echo "  • Paste normally and press ENTER."
echo

case "$MEDIA_PROFILE" in
  jellyfin)
    echo "Jellyfin requires an API key."
    echo
    echo "How to get it:"
    echo "  1) Open Jellyfin Web UI"
    echo "  2) Dashboard → API Keys"
    echo "  3) Create a new API key"
    echo
    echo "Paste ONLY the API key value below:"
    MEDIA_API_KEY="$(require_non_empty "Enter Jellyfin API Key")"
    ;;
  plex)
    echo "Plex requires a USER TOKEN (NOT an API key)."
    echo
    echo "How to get it:"
    echo "  1) Open Plex Web App and ensure you are logged in"
    echo "  2) Visit: https://plex.tv/devices.xml"
    echo "  3) Copy the value of X-Plex-Token"
    echo
    echo "⚠️  IMPORTANT:"
    echo "  • Paste ONLY the token value"
    echo "  • Do NOT include 'token='"
    echo "  • Do NOT paste XML or URLs"
    echo
    echo "Paste the token below:"
    MEDIA_API_KEY="$(require_non_empty "Enter Plex X-Plex-Token")"
    ;;
  emby)
    echo "Emby requires an API key."
    echo
    echo "How to get it:"
    echo "  1) Open Emby Web UI"
    echo "  2) Settings → Advanced → API Keys"
    echo "  3) Create a new API key"
    echo
    echo "Paste ONLY the API key value below:"
    MEDIA_API_KEY="$(require_non_empty "Enter Emby API Key")"
    ;;
esac

banner "Frontend Origin"
ORIGIN="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " USE_PROXY
[[ "${USE_PROXY,,}" == "y" ]] && ORIGIN="$(require_url "Public frontend URL")"
ok "ORIGIN=$ORIGIN"

banner "Downloader Selection (REQUIRED)"

echo "• API keys entered below will be masked for security."
echo

echo "Choose ONE downloader service:"
echo
echo "1) Real-Debrid"
echo "2) All-Debrid"
echo "3) Debrid-Link"
echo

read -rp "Select ONE: " DL_SEL

RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=false

RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=""
RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=""
RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=""

case "$DL_SEL" in
  1)
    RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=true
    echo
    echo "Real-Debrid API Token required."
    echo
    echo "How to get it:"
    echo "  1) Visit https://real-debrid.com/apitoken"
    echo "  2) Copy the API Token shown"
    echo
    echo "Paste ONLY the API token value below:"
    RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY="$(require_non_empty "Enter Real-Debrid API Token")"
    ;;
  2)
    RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=true
    echo
    echo "All-Debrid API Key required."
    echo
    echo "How to get it:"
    echo "  1) Visit https://alldebrid.com/apikeys"
    echo "  2) Generate or copy an existing key"
    echo
    echo "Paste ONLY the API key value below:"
    RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY="$(require_non_empty "Enter All-Debrid API Key")"
    ;;
  3)
    RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=true
    echo
    echo "Debrid-Link API Key required."
    echo
    echo "How to get it:"
    echo "  1) Visit https://debrid-link.com/webapp/apikey"
    echo "  2) Copy your API key"
    echo
    echo "Paste ONLY the API key value below:"
    RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY="$(require_non_empty "Enter Debrid-Link API Key")"
    ;;
  *)
    fail "Downloader selection REQUIRED"
    ;;
esac

banner "Scraper Selection (REQUIRED)"

echo "Choose ONE scraping backend:"
echo
echo "1) Torrentio   (No config required)"
echo "2) Prowlarr    (Local instance only)"
echo "3) Comet       (Public or self-hosted)"
echo "4) Jackett     (Local instance only)"
echo "5) Zilean      (Public or self-hosted)"
echo

read -rp "Select ONE: " SCR_SEL

RIVEN_SCRAPING_TORRENTIO_ENABLED=false
RIVEN_SCRAPING_PROWLARR_ENABLED=false
RIVEN_SCRAPING_COMET_ENABLED=false
RIVEN_SCRAPING_JACKETT_ENABLED=false
RIVEN_SCRAPING_ZILEAN_ENABLED=false

RIVEN_SCRAPING_PROWLARR_URL=""
RIVEN_SCRAPING_PROWLARR_API_KEY=""
RIVEN_SCRAPING_COMET_URL=""
RIVEN_SCRAPING_JACKETT_URL=""
RIVEN_SCRAPING_JACKETT_API_KEY=""
RIVEN_SCRAPING_ZILEAN_URL=""

case "$SCR_SEL" in
  1)
    RIVEN_SCRAPING_TORRENTIO_ENABLED=true
    echo
    echo "Torrentio selected."
    echo "• Uses public Torrentio endpoint"
    echo "• No configuration required"
    ;;
  2)
    RIVEN_SCRAPING_PROWLARR_ENABLED=true
    echo
    echo "Prowlarr selected."
    echo
    echo "Example:"
    echo "  • http://localhost:9696"
    echo
    echo "API Key location:"
    echo "  Settings → General → API Key"
    echo
    RIVEN_SCRAPING_PROWLARR_URL="$(require_url "Enter Prowlarr URL")"
    RIVEN_SCRAPING_PROWLARR_API_KEY="$(read_masked_non_empty "Enter Prowlarr API Key")"
    ;;
  3)
    RIVEN_SCRAPING_COMET_ENABLED=true
    echo
    echo "Comet selected."
    echo
    echo "Examples:"
    echo "  • Public: https://cometfortheweebs.midnightignite.me"
    echo "  • Local:  http://localhost:<port>"
    echo
    echo "No API key is required."
    echo
    RIVEN_SCRAPING_COMET_URL="$(require_url "Enter Comet base URL")"
    ;;
  4)
    RIVEN_SCRAPING_JACKETT_ENABLED=true
    echo
    echo "Jackett selected."
    echo
    echo "Example:"
    echo "  • http://localhost:9117"
    echo
    echo "API Key location:"
    echo "  Jackett Web UI → Top-right corner"
    echo
    RIVEN_SCRAPING_JACKETT_URL="$(require_url "Enter Jackett URL")"
    RIVEN_SCRAPING_JACKETT_API_KEY="$(read_masked_non_empty "Enter Jackett API Key")"
    ;;
  5)
    RIVEN_SCRAPING_ZILEAN_ENABLED=true
    echo
    echo "Zilean selected."
    echo
    echo "Examples:"
    echo "  • Public: https://zilean.example.com"
    echo "  • Local:  http://localhost:<port>"
    echo
    echo "No API key is required."
    echo
    RIVEN_SCRAPING_ZILEAN_URL="$(require_url "Enter Zilean base URL")"
    ;;
  *)
    fail "Scraper selection REQUIRED"
    ;;
esac

POSTGRES_PASSWORD="$(openssl rand -hex 24)"
AUTH_SECRET="$(openssl rand -base64 32)"

set +o pipefail
BACKEND_API_KEY="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
set -o pipefail

if [ "${#BACKEND_API_KEY}" -ne 32 ]; then
  fail "Invalid BACKEND_API_KEY generated (expected 32, got ${#BACKEND_API_KEY})"
fi

RIVEN_UPDATERS_JELLYFIN_ENABLED=false
RIVEN_UPDATERS_PLEX_ENABLED=false
RIVEN_UPDATERS_EMBY_ENABLED=false

RIVEN_UPDATERS_JELLYFIN_API_KEY=""
RIVEN_UPDATERS_PLEX_TOKEN=""
RIVEN_UPDATERS_EMBY_API_KEY=""

case "$MEDIA_PROFILE" in
  jellyfin)
    RIVEN_UPDATERS_JELLYFIN_ENABLED=true
    RIVEN_UPDATERS_JELLYFIN_API_KEY="$MEDIA_API_KEY"
    ;;
  plex)
    RIVEN_UPDATERS_PLEX_ENABLED=true
    RIVEN_UPDATERS_PLEX_TOKEN="$MEDIA_API_KEY"
    ;;
  emby)
    RIVEN_UPDATERS_EMBY_ENABLED=true
    RIVEN_UPDATERS_EMBY_API_KEY="$MEDIA_API_KEY"
    ;;
esac

banner ".env Generation"
cat > .env <<EOF_ENV
TZ="$TZ_SELECTED"
ORIGIN="$ORIGIN"
MEDIA_PROFILE="$MEDIA_PROFILE"

POSTGRES_DB="riven"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

BACKEND_API_KEY="$BACKEND_API_KEY"
AUTH_SECRET="$AUTH_SECRET"

RIVEN_UPDATERS_LIBRARY_PATH="$BACKEND_PATH"
RIVEN_UPDATERS_UPDATER_INTERVAL="120"

RIVEN_UPDATERS_JELLYFIN_ENABLED="$RIVEN_UPDATERS_JELLYFIN_ENABLED"
RIVEN_UPDATERS_JELLYFIN_API_KEY="$RIVEN_UPDATERS_JELLYFIN_API_KEY"
RIVEN_UPDATERS_JELLYFIN_URL="http://jellyfin:8096"

RIVEN_UPDATERS_PLEX_ENABLED="$RIVEN_UPDATERS_PLEX_ENABLED"
RIVEN_UPDATERS_PLEX_TOKEN="$RIVEN_UPDATERS_PLEX_TOKEN"
RIVEN_UPDATERS_PLEX_URL="http://plex:32400"

RIVEN_UPDATERS_EMBY_ENABLED="$RIVEN_UPDATERS_EMBY_ENABLED"
RIVEN_UPDATERS_EMBY_API_KEY="$RIVEN_UPDATERS_EMBY_API_KEY"
RIVEN_UPDATERS_EMBY_URL="http://emby:8097"

RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED="$RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED"
RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY="$RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY"

RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED="$RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED"
RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY="$RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY"

RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED="$RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED"
RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY="$RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY"

RIVEN_SCRAPING_TORRENTIO_ENABLED="$RIVEN_SCRAPING_TORRENTIO_ENABLED"
RIVEN_SCRAPING_PROWLARR_ENABLED="$RIVEN_SCRAPING_PROWLARR_ENABLED"
RIVEN_SCRAPING_PROWLARR_URL="$RIVEN_SCRAPING_PROWLARR_URL"
RIVEN_SCRAPING_PROWLARR_API_KEY="$RIVEN_SCRAPING_PROWLARR_API_KEY"

RIVEN_SCRAPING_COMET_ENABLED="$RIVEN_SCRAPING_COMET_ENABLED"
RIVEN_SCRAPING_COMET_URL="$RIVEN_SCRAPING_COMET_URL"

RIVEN_SCRAPING_JACKETT_ENABLED="$RIVEN_SCRAPING_JACKETT_ENABLED"
RIVEN_SCRAPING_JACKETT_URL="$RIVEN_SCRAPING_JACKETT_URL"
RIVEN_SCRAPING_JACKETT_API_KEY="$RIVEN_SCRAPING_JACKETT_API_KEY"

RIVEN_SCRAPING_ZILEAN_ENABLED="$RIVEN_SCRAPING_ZILEAN_ENABLED"
RIVEN_SCRAPING_ZILEAN_URL="$RIVEN_SCRAPING_ZILEAN_URL"
EOF_ENV

banner "Fixing .env formatting issues"
awk '
  BEGIN { key=""; val="" }
  {
    if (key != "") {
      val = val $0
      if ($0 ~ /"$/) {
        gsub(/\n/, "", val)
        sub(/"$/, "", val)
        print key "\"" val "\""
        key=""
        val=""
      }
      next
    }

    if ($0 ~ /^[A-Z0-9_]+="$/) {
      split($0, a, "=")
      key = a[1] "="
      val = ""
      next
    }

    print
  }
' .env > .env.fixed

mv .env.fixed .env
ok ".env repaired and sanitized"

banner "Starting Riven"
docker compose up -d
ok "Riven started"

banner "INSTALL COMPLETE"
