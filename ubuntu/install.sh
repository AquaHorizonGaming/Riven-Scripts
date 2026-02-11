#!/usr/bin/env bash
set -euo pipefail

DEBUG_MODE=false
if [[ "${1:-}" == "--debug" ]]; then
  DEBUG_MODE=true
  shift
fi

############################################
# CONSTANTS
############################################
INSTALL_DIR="/opt/riven"
BACKEND_PATH="/mnt/riven/backend"
MOUNT_PATH="/mnt/riven/mount"
LOG_DIR="/tmp/logs/riven"

MEDIA_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.media.yml"
RIVEN_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"

DEFAULT_ORIGIN="http://localhost:3000"

INSTALL_VERSION="v0.6.8"

############################################
# HELPERS
############################################
banner(){ echo -e "\n========================================\n $1\n========================================"; }
ok()   { printf "✔  %s\n" "$1"; }
warn() { printf "⚠  %s\n" "$1"; }
fail() { printf "✖  %s\n" "$1"; exit 1; }

# Capture whether the original stdout is a terminal before logging redirection.
exec 3>&1
ORIGINAL_STDOUT_IS_TTY=false
[[ -t 3 ]] && ORIGINAL_STDOUT_IS_TTY=true

run_docker_compose_up_detached() {
  local -a compose_cmd=("$@")

  if [[ "$ORIGINAL_STDOUT_IS_TTY" == "true" ]]; then
    # Preserve TTY behavior so pull progress updates in-place.
    "${compose_cmd[@]}" up -d --pull always 1>&3 2>&3
  else
    # Keep normal output in CI / non-interactive shells.
    "${compose_cmd[@]}" up -d --pull always
  fi
}

############################################
# REQUIRED NON-EMPTY (SILENT)
# (keep for non-secret values if needed)
############################################
require_non_empty() {
  local prompt="$1" val
  while true; do
    IFS= read -r -p "$prompt: " val
    val="$(printf '%s' "$val" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    warn "Value required"
  done
}

############################################
# REQUIRED NON-EMPTY (MASKED ****)
# For API keys / tokens / secrets
############################################
read_masked_non_empty() {
  local prompt="$1"
  local val="" char

  while true; do
    val=""
    printf "%s: " "$prompt"

    while IFS= read -r -s -n1 char; do
      [[ $char == $'\n' ]] && break

      # Handle backspace
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

    # Trim whitespace
    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    warn "Value required"
  done
}

############################################
# URL VALIDATION
############################################
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

############################################
# OS CHECK (Ubuntu only, WSL warned)
############################################
banner "OS Check"

require_ubuntu() {
  # Must be Linux
  if [[ "$(uname -s)" != "Linux" ]]; then
    fail "This installer must be run on Ubuntu Linux. Detected: $(uname -s)"
  fi

  # Detect WSL
  if grep -qi microsoft /proc/version 2>/dev/null; then
    warn "WSL detected — this is not recommended"
    read -rp "Continue anyway? [y/N]: " yn
    [[ "${yn:-}" =~ ^[Yy]$ ]] || exit 1
  fi

  # Must have os-release
  if [[ ! -f /etc/os-release ]]; then
    fail "Cannot determine OS (missing /etc/os-release)"
  fi

  # Must be Ubuntu
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu required."
  fi

  ok "Ubuntu detected (${PRETTY_NAME})"
}

require_ubuntu

############################################
# ROOT CHECK
############################################
[[ "$(id -u)" -eq 0 ]] || fail "Run with sudo"

############################################
# INSTALLER VERSION
############################################
banner "Version"

print_installer_version() {
  : "${INSTALL_VERSION:=unknown}"
  ok "Installer version: ${INSTALL_VERSION}"
}

print_installer_version


############################################
# LOGGING MODULE
############################################
banner "Logging"

LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Mirror stdout + stderr to terminal AND log
exec > >(tee -a "$LOG_FILE") 2>&1

log()        { echo "[INFO]  $*"; }
log_warn()   { echo "[WARN]  $*"; }
log_error()  { echo "[ERROR] $*"; }
log_section(){ echo -e "\n========== $* ==========\n"; }

if [[ "$DEBUG_MODE" == "true" ]]; then
  export PS4='+ [${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}] '
  set -x
  debug "Debug mode enabled"
  debug "original_stdout_is_tty=$ORIGINAL_STDOUT_IS_TTY"
fi

trap 'rc=$?; cmd=${BASH_COMMAND:-unknown}; log_error "Installer exited unexpectedly at line $LINENO (rc=$rc, cmd: $cmd)"; debug "failure_context rc=$rc cmd=$cmd"; exit $rc' ERR

log "Logging initialized"
log "Log file: $LOG_FILE"

############################################
# TIMEZONE (INSTALLER SAFE)
############################################
banner "Timezone"
debug_step "timezone detection and configuration"

detect_timezone() {
  timedatectl show --property=Timezone --value 2>/dev/null \
    || cat /etc/timezone 2>/dev/null \
    || echo UTC
}

TZ_DETECTED="$(detect_timezone)"
read -rp "Timezone [$TZ_DETECTED]: " TZ_INPUT
TZ_SELECTED="${TZ_INPUT:-$TZ_DETECTED}"

if [[ ! -f "/usr/share/zoneinfo/$TZ_SELECTED" ]]; then
  fail "Invalid timezone: $TZ_SELECTED"
fi

ln -sf "/usr/share/zoneinfo/$TZ_SELECTED" /etc/localtime
echo "$TZ_SELECTED" > /etc/timezone

ok "Timezone set: $TZ_SELECTED"

############################################
# SYSTEM DEPS
############################################
banner "System Dependencies"
debug_step "system dependency verification"

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
  # Prefer the sudo user if present
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    TARGET_UID="$(id -u "$SUDO_USER")"
    TARGET_GID="$(id -g "$SUDO_USER")"
    return
  fi

  # Fallback: first non-root user with UID >= 1000
  local user
  user="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"

  if [[ -n "$user" ]]; then
    TARGET_UID="$(id -u "$user")"
    TARGET_GID="$(id -g "$user")"
    return
  fi

  # Absolute fallback
  TARGET_UID=1000
  TARGET_GID=1000
}

detect_uid_gid

ok "Detected user ownership: UID=$TARGET_UID GID=$TARGET_GID"

############################################
# DOCKER
############################################
banner "Docker"
debug_step "docker installation check"

if command -v docker >/dev/null 2>&1; then
  ok "Docker already installed"
else
  echo "[*] Installing Docker — this may take several minutes depending on your connection..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  ok "Docker installed"
fi

############################################
# DOCKER GROUP / USER PERMISSIONS
############################################
banner "DockerGroup"

setup_docker_group() {
  # Ensure docker group exists
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker || fail "Failed to create docker group"
    ok "Docker group created"
  else
    ok "Docker group already exists"
  fi

  # Determine target user
  local user=""
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    user="$SUDO_USER"
  else
    user="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"
  fi

  if [[ -z "$user" ]]; then
    warn "No non-root user found to add to docker group"
    return
  fi

  # Add user to docker group if not already a member
  if id -nG "$user" | grep -qw docker; then
    ok "User '$user' already in docker group"
  else
    usermod -aG docker "$user" || fail "Failed to add $user to docker group"
    ok "User '$user' added to docker group"
    warn "Log out and back in for Docker permissions to apply"
  fi
}

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
  local MOUNT_PATH="/mnt/riven/mount"
  local SERVICE_NAME="riven-bind-shared.service"

  banner "Ensuring rshared mount for Riven"

  mkdir -p "$MOUNT_PATH"

  # If already shared, do nothing
  if findmnt -no PROPAGATION "$MOUNT_PATH" 2>/dev/null | grep -q shared; then
    ok "Mount already rshared"
    return
  fi

  warn "Mount is not rshared — installing systemd unit"

  cat >/etc/systemd/system/$SERVICE_NAME <<EOF
[Unit]
Description=Make Riven mount bind shared
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --bind $MOUNT_PATH $MOUNT_PATH
ExecStart=/usr/bin/mount --make-rshared $MOUNT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"

  # Re-check
  if findmnt -no PROPAGATION "$MOUNT_PATH" | grep -q shared; then
    ok "rshared mount enforced"
  else
    fail "Failed to enforce rshared mount on $MOUNT_PATH"
  fi
}


sudo mount --bind $MOUNT_PATH $MOUNT_PATH
sudo mount --make-rshared $MOUNT_PATH

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

############################################
# START MEDIA SERVER 
############################################
banner "Starting Media Server"
run_docker_compose_up_detached docker compose -f docker-compose.media.yml --profile "$MEDIA_PROFILE"
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

############################################
# MEDIA AUTH TOKEN / API KEY
############################################
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

############################################
# FRONTEND ORIGIN 
############################################
banner "Frontend Origin"
ORIGIN="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " USE_PROXY
[[ "${USE_PROXY,,}" == "y" ]] && ORIGIN="$(require_url "Public frontend URL")"
ok "ORIGIN=$ORIGIN"

############################################
# DOWNLOADER SELECTION (REQUIRED)
############################################
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

############################################
# SCRAPER SELECTION (MULTI-SELECT, REQUIRED)
############################################
banner "Scraper Selection (REQUIRED)"

echo "Select one or more scraping backends."
echo "Enter numbers separated by spaces or commas (example: 1 3 5 or 1,3,5)"
echo ""
echo "1) Torrentio   (No config required)"
echo "2) Prowlarr    (Local instance only)"
echo "3) Comet       (Public or self-hosted)"
echo "4) Jackett     (Local instance only)"
echo "5) Zilean      (Public or self-hosted)"
echo ""

read -rp "Select one or more: " SCR_SEL_RAW

# Normalize commas → spaces, collapse whitespace
SCR_SEL="$(echo "$SCR_SEL_RAW" | tr ',' ' ' | xargs)"

# Reset all flags
RIVEN_SCRAPING_TORRENTIO_ENABLED=false
RIVEN_SCRAPING_PROWLARR_ENABLED=false
RIVEN_SCRAPING_COMET_ENABLED=false
RIVEN_SCRAPING_JACKETT_ENABLED=false
RIVEN_SCRAPING_ZILEAN_ENABLED=false

# Reset config values
RIVEN_SCRAPING_PROWLARR_URL=""
RIVEN_SCRAPING_PROWLARR_API_KEY=""
RIVEN_SCRAPING_COMET_URL=""
RIVEN_SCRAPING_JACKETT_URL=""
RIVEN_SCRAPING_JACKETT_API_KEY=""
RIVEN_SCRAPING_ZILEAN_URL=""

VALID_SELECTION=false

for sel in $SCR_SEL; do
  case "$sel" in
    1)
      RIVEN_SCRAPING_TORRENTIO_ENABLED=true
      VALID_SELECTION=true
      log "Torrentio enabled"
      ;;
    2)
      RIVEN_SCRAPING_PROWLARR_ENABLED=true
      VALID_SELECTION=true

      echo ""
      echo "Prowlarr configuration"
      echo "Example: http://localhost:9696"
      echo "API Key: Settings → General → API Key"

      RIVEN_SCRAPING_PROWLARR_URL="$(require_url "Enter Prowlarr URL")"
      RIVEN_SCRAPING_PROWLARR_API_KEY="$(read_masked_non_empty "Enter Prowlarr API Key")"

      log "Prowlarr enabled"
      ;;
    3)
      RIVEN_SCRAPING_COMET_ENABLED=true
      VALID_SELECTION=true

      echo ""
      echo "Comet configuration"
      echo "Examples:"
      echo " • https://cometfortheweebs.midnightignite.me"
      echo " • http://localhost:<port>"

      RIVEN_SCRAPING_COMET_URL="$(require_url "Enter Comet base URL")"

      log "Comet enabled"
      ;;
    4)
      RIVEN_SCRAPING_JACKETT_ENABLED=true
      VALID_SELECTION=true

      echo ""
      echo "Jackett configuration"
      echo "Example: http://localhost:9117"
      echo "API Key: Jackett Web UI → Top-right corner"

      RIVEN_SCRAPING_JACKETT_URL="$(require_url "Enter Jackett URL")"
      RIVEN_SCRAPING_JACKETT_API_KEY="$(read_masked_non_empty "Enter Jackett API Key")"

      log "Jackett enabled"
      ;;
    5)
      RIVEN_SCRAPING_ZILEAN_ENABLED=true
      VALID_SELECTION=true

      echo ""
      echo "Zilean configuration"
      echo "Examples:"
      echo " • https://zilean.example.com"
      echo " • http://localhost:<port>"

      RIVEN_SCRAPING_ZILEAN_URL="$(require_url "Enter Zilean base URL")"

      log "Zilean enabled"
      ;;
    *)
      warn "Invalid scraper option ignored: $sel"
      ;;
  esac
done

if [[ "$VALID_SELECTION" != "true" ]]; then
  fail "At least one scraper must be selected"
fi

echo ""
echo "Enabled scrapers:"
[[ "$RIVEN_SCRAPING_TORRENTIO_ENABLED" == "true" ]] && echo " • Torrentio"
[[ "$RIVEN_SCRAPING_PROWLARR_ENABLED" == "true" ]] && echo " • Prowlarr"
[[ "$RIVEN_SCRAPING_COMET_ENABLED" == "true" ]] && echo " • Comet"
[[ "$RIVEN_SCRAPING_JACKETT_ENABLED" == "true" ]] && echo " • Jackett"
[[ "$RIVEN_SCRAPING_ZILEAN_ENABLED" == "true" ]] && echo " • Zilean"
echo ""

############################################
# SECRETS
############################################
POSTGRES_PASSWORD="$(openssl rand -hex 24)"
AUTH_SECRET="$(openssl rand -base64 32)"


############################################
# RIVEN API KEY MODULE
# Order: Generate → Validate → Continue
############################################

# ------------------------------------------
# PART 1: Generate API key
# ------------------------------------------
# Generate backend API key safely under pipefail
set +o pipefail
BACKEND_API_KEY="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
set -o pipefail


# ------------------------------------------
# PART 2: Validate using Riven's logic
# ------------------------------------------
if [ "${#BACKEND_API_KEY}" -ne 32 ]; then
  echo
  echo "============================================"
  echo "❌ RIVEN INSTALL ERROR: API KEY GENERATION"
  echo "============================================"
  echo
  echo "An invalid BACKEND_API_KEY was generated."
  echo
  echo "Expected length : 32 characters"
  echo "Actual length   : ${#BACKEND_API_KEY}"
  echo
  echo "This should NEVER happen under normal"
  echo "conditions and likely indicates one of:"
  echo "  • /dev/urandom is unavailable"
  echo "  • Shell I/O truncation"
  echo "  • Environment corruption"
  echo
  echo "Installation cannot continue safely."
  echo "Please investigate the system environment"
  echo "and re-run the installer."
  echo
  echo "============================================"
  echo
  exit 1
fi

############################################
# MEDIA UPDATER FLAGS
############################################
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

############################################
# VALIDATION SUMMARY (CONFIRM BEFORE CONTINUE)
############################################
banner "Configuration Summary"
debug_step "print configuration summary and collect confirmation"

echo "Please review your configuration below:"
echo ""
debug "summary timezone=$TZ_SELECTED origin=$ORIGIN media_profile=$MEDIA_PROFILE media_url=http://$SERVER_IP:$MEDIA_PORT"
debug "summary downloader_flags rd=${RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED:-unset} ad=${RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED:-unset} dl=${RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED:-unset}"
debug "summary secrets_present media_api_key_set=$([[ -n "${MEDIA_API_KEY:-}" ]] && echo true || echo false) backend_api_key_set=$([[ -n "${BACKEND_API_KEY:-}" ]] && echo true || echo false) auth_secret_set=$([[ -n "${AUTH_SECRET:-}" ]] && echo true || echo false)"

echo "🕒 Timezone"
echo "  • $TZ_SELECTED"
echo ""

echo "🌍 Frontend Origin"
echo "  • $ORIGIN"
echo ""

echo "🎬 Media Server"
echo "  • Selected: $MEDIA_PROFILE"
echo "  • URL: http://$SERVER_IP:$MEDIA_PORT"
echo ""

echo "⬇️ Downloader"
if [[ "$RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED" == "true" ]]; then
  echo "  • Real-Debrid"
elif [[ "$RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED" == "true" ]]; then
  echo "  • All-Debrid"
elif [[ "$RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED" == "true" ]]; then
  echo "  • Debrid-Link"
else
  echo "  • NONE (invalid)"
fi
echo ""

echo "🔍 Scrapers Enabled"
SCRAPER_COUNT=0

if [[ "${RIVEN_SCRAPING_TORRENTIO_ENABLED:-false}" == "true" ]]; then
  echo "  • Torrentio"
  ((++SCRAPER_COUNT))
fi

if [[ "${RIVEN_SCRAPING_PROWLARR_ENABLED:-false}" == "true" ]]; then
  echo "  • Prowlarr"
  ((++SCRAPER_COUNT))
fi

if [[ "${RIVEN_SCRAPING_COMET_ENABLED:-false}" == "true" ]]; then
  echo "  • Comet"
  ((++SCRAPER_COUNT))
fi

if [[ "${RIVEN_SCRAPING_JACKETT_ENABLED:-false}" == "true" ]]; then
  echo "  • Jackett"
  ((++SCRAPER_COUNT))
fi

if [[ "${RIVEN_SCRAPING_ZILEAN_ENABLED:-false}" == "true" ]]; then
  echo "  • Zilean"
  ((++SCRAPER_COUNT))
fi

if [[ "$SCRAPER_COUNT" -eq 0 ]]; then
  echo "  • NONE (invalid)"
fi

echo ""
echo "📁 Paths"
echo "  • Install Dir:  $INSTALL_DIR"
echo "  • Backend Path: $BACKEND_PATH"
echo "  • Mount Path:   $MOUNT_PATH"
echo ""

echo "👤 Ownership"
echo "  • UID:GID $TARGET_UID:$TARGET_GID"
echo ""

echo "⚠️  IMPORTANT"
echo "  • This will write configuration files"
echo "  • Docker containers will be started"
echo "  • Secrets will be generated automatically"
echo ""

read -rp "Continue with this configuration? [y/N]: " CONFIRM
if [[ ! "${CONFIRM,,}" =~ ^y$ ]]; then
  echo ""
  echo "Installation aborted by user."
  exit 1
fi

ok "Configuration confirmed"

############################################
# WRITE .env (ONCE, NO SED)
############################################
banner ".env Generation"

cat > .env <<EOF
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
EOF

############################################
# FIX BROKEN MULTILINE ENV VALUES
############################################
banner "Fixing .env formatting issues"

awk '
  BEGIN { key=""; val="" }
  {
    # If we are currently accumulating a broken value
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

    # Detect start of broken quoted value
    if ($0 ~ /^[A-Z0-9_]+="$/) {
      split($0, a, "=")
      key = a[1] "="
      val = ""
      next
    }

    # Normal line
    print
  }
' .env > .env.fixed

mv .env.fixed .env

ok ".env repaired and sanitized"


############################################
# START RIVEN
############################################
banner "Starting Riven"
run_docker_compose_up_detached docker compose
ok "Riven started"

banner "INSTALL COMPLETE"

############################################
# INSTALL SUMMARY MODULE
############################################
banner "Riven Installation Summary"

echo "📁 Paths"
echo "  • Install Dir:        $INSTALL_DIR"
echo "  • Backend Path:       $BACKEND_PATH"
echo "  • Mount Path:         $MOUNT_PATH"
echo

echo "👤 Ownership"
echo "  • UID:GID             $TARGET_UID:$TARGET_GID"
echo

echo "🌍 Frontend"
echo "  • ORIGIN:             $ORIGIN"
echo

echo "🎬 Media Server"
echo "  • Selected:           $MEDIA_PROFILE"
echo "  • URL:                http://$SERVER_IP:$MEDIA_PORT"
echo "  • Updater Enabled:    $(
  case "$MEDIA_PROFILE" in
    jellyfin) echo "$RIVEN_UPDATERS_JELLYFIN_ENABLED" ;;
    plex)     echo "$RIVEN_UPDATERS_PLEX_ENABLED" ;;
    emby)     echo "$RIVEN_UPDATERS_EMBY_ENABLED" ;;
  esac
)"
echo

echo "⬇️ Downloader"
if [[ "$RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED" == "true" ]]; then
  echo "  • Real-Debrid (enabled)"
elif [[ "$RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED" == "true" ]]; then
  echo "  • All-Debrid (enabled)"
elif [[ "$RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED" == "true" ]]; then
  echo "  • Debrid-Link (enabled)"
else
  echo "  • NONE (❌ invalid state)"
fi
echo

echo "🔍 Scraper"
if [[ "$RIVEN_SCRAPING_TORRENTIO_ENABLED" == "true" ]]; then
  echo "  • Torrentio"
elif [[ "$RIVEN_SCRAPING_PROWLARR_ENABLED" == "true" ]]; then
  echo "  • Prowlarr ($RIVEN_SCRAPING_PROWLARR_URL)"
else
  echo "  • NONE (❌ invalid state)"
fi
echo

echo "🗄️ Database"
echo "  • Postgres DB:        riven"
echo "  • User:               postgres"
echo
echo "  • POSTGRES PASSWORD:      $POSTGRES_PASSWORD"
echo "  • BACKEND API KEY:      $BACKEND_API_KEY"
echo "  • AUTH SECRET:      $AUTH_SECRET"



echo "🐳 Docker"
echo "  • Media Compose:      $INSTALL_DIR/docker-compose.media.yml"
echo "  • Riven Compose:      $INSTALL_DIR/docker-compose.yml"
echo "  • Media Profile:      $MEDIA_PROFILE"
echo

echo "📦 Environment"
echo "  • .env Location:     $INSTALL_DIR/.env"
echo "  • Permissions:       600"
echo

echo "🎥 Media Server"
echo "➡️  Open your media server in a browser:"
echo "👉  http://$SERVER_IP:$MEDIA_PORT" 

echo "🧠 Notes"
echo "  • rshared mount enforced via systemd"
echo "  • Media server started first"
echo "  • Riven started after config complete"
echo

ok "Riven is ready 🚀"
