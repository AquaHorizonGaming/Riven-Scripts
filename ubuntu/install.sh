#!/usr/bin/env bash
set -euo pipefail

############################################
# CONSTANTS
############################################
INSTALL_DIR="/opt/riven"                 # ALWAYS Linux FS
BACKEND_PATH="/mnt/riven/backend"        # overridden on WSL
MOUNT_PATH="/mnt/riven/mount"            # overridden on WSL
LOG_DIR="/tmp/logs/riven"

MEDIA_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.media.yml"
RIVEN_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"

DEFAULT_ORIGIN="http://localhost:3000"
INSTALL_VERSION="v0.5.8"

############################################
# HELPERS
############################################
banner(){ echo -e "\n========================================\n $1\n========================================"; }
ok(){ printf "✔  %s\n" "$1"; }
warn(){ printf "⚠  %s\n" "$1"; }
fail(){ printf "✖  %s\n" "$1"; exit 1; }

require_non_empty() {
  local prompt="$1" val
  while true; do
    read -rp "$prompt: " val
    val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$val" ]] && { printf "%s" "$val"; return; }
    warn "Value required"
  done
}

require_url() {
  local prompt="$1" val
  while true; do
    read -rp "$prompt: " val
    [[ "$val" =~ ^https?:// ]] && { printf "%s" "$val"; return; }
    warn "Must start with http:// or https://"
  done
}

############################################
# OS / WSL DETECTION
############################################
banner "OS Check"

IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  IS_WSL=true
fi

[[ "$(uname -s)" == "Linux" ]] || fail "Linux required"
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || fail "Ubuntu rootfs required"

if [[ "$IS_WSL" == true ]]; then
  ok "WSL detected (Ubuntu rootfs: ${PRETTY_NAME})"
else
  ok "Native Ubuntu detected (${PRETTY_NAME})"
fi

############################################
# ROOT CHECK
############################################
[[ "$(id -u)" -eq 0 ]] || fail "Run with sudo"

############################################
# LOGGING (WSL HONEST)
############################################
banner "Logging"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'fail "Installer failed at line $LINENO"' ERR

if [[ "$IS_WSL" == true ]]; then
  WIN_LOG_PATH="\\\\wsl$\\${WSL_DISTRO_NAME:-Ubuntu}${LOG_FILE}"
  ok "Log file (WSL): $LOG_FILE"
  ok "Windows path:   $WIN_LOG_PATH"
else
  ok "Log file: $LOG_FILE"
fi

############################################
# PATH MODEL
############################################
banner "Filesystem Model"

WSL_DRVFS=false
if [[ "$IS_WSL" == true && -d /mnt/c ]]; then
  BACKEND_PATH="/mnt/c/riven/backend"
  MOUNT_PATH="/mnt/c/riven/mount"
  WSL_DRVFS=true
  ok "WSL data paths: /mnt/c/riven/* (Windows-backed)"
else
  ok "Linux data paths: /mnt/riven/*"
fi

ok "Config path (always Linux FS): $INSTALL_DIR"

############################################
# TIMEZONE (NO LIES)
############################################
banner "Timezone"

if [[ "$IS_WSL" == true ]]; then
  warn "WSL detected — timezone controlled by Windows"
  ok "Timezone inherited from Windows"
else
  TZ_SELECTED="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
  ln -sf "/usr/share/zoneinfo/$TZ_SELECTED" /etc/localtime
  echo "$TZ_SELECTED" > /etc/timezone
  ok "Timezone set: $TZ_SELECTED"
fi

############################################
# SYSTEM DEPENDENCIES
############################################
banner "System Dependencies"

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl fuse3
ok "Dependencies installed"

############################################
# USER CONTEXT
############################################
banner "User Context"

TARGET_UID="${SUDO_UID:-1000}"
TARGET_GID="$(id -g "${SUDO_USER:-root}" 2>/dev/null || echo 1000)"
ok "UID:GID = $TARGET_UID:$TARGET_GID"

############################################
# DOCKER + COMPOSE SETUP
############################################
banner "Docker"

if ! command -v docker >/dev/null; then
  if [[ "$IS_WSL" == true ]]; then
    fail "Docker CLI missing. Install Docker Desktop and enable WSL integration."
  else
    curl -fsSL https://get.docker.com | sh
  fi
fi

# Ensure daemon reachable
docker info >/dev/null 2>&1 || fail "Docker daemon not reachable"

# Compose command wrapper
COMPOSE_MODE=""

compose() {
  case "$COMPOSE_MODE" in
    v2) docker compose "$@" ;;
    v1) docker-compose "$@" ;;
    *)  fail "Compose not initialized" ;;
  esac
}

install_compose_v2_plugin() {
  local arch url dest
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) fail "Unsupported arch for compose plugin: $(uname -m)" ;;
  esac

  url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"

  # Prefer standard plugin dir. Docker scans these:
  # - /usr/local/lib/docker/cli-plugins
  # - /usr/lib/docker/cli-plugins (varies)
  # - ~/.docker/cli-plugins
  mkdir -p /usr/local/lib/docker/cli-plugins

  dest="/usr/local/lib/docker/cli-plugins/docker-compose"

  warn "Installing Docker Compose v2 plugin to: $dest"
  curl -fsSL "$url" -o "$dest" || fail "Failed to download compose plugin"
  chmod +x "$dest" || true

  # Verify
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose v2 installed"
    return 0
  fi

  # Fallback to user plugin path if system path isn't picked up
  mkdir -p /root/.docker/cli-plugins
  cp -f "$dest" /root/.docker/cli-plugins/docker-compose
  chmod +x /root/.docker/cli-plugins/docker-compose || true

  docker compose version >/dev/null 2>&1 || fail "Compose plugin installed but not detected by Docker"
  ok "Docker Compose v2 installed (user plugin path)"
}

# Detect compose availability
if docker compose version >/dev/null 2>&1; then
  COMPOSE_MODE="v2"
  ok "Compose: docker compose (v2)"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_MODE="v1"
  ok "Compose: docker-compose (v1)"
else
  # Auto-install v2 plugin
  install_compose_v2_plugin
  COMPOSE_MODE="v2"
  ok "Compose: docker compose (v2)"
fi

ok "Docker ready"

############################################
# FILESYSTEM SETUP
############################################
banner "Filesystem Setup"

mkdir -p "$INSTALL_DIR" "$BACKEND_PATH" "$MOUNT_PATH"

if [[ "$WSL_DRVFS" == true ]]; then
  warn "Skipping chown on Windows-backed filesystem"
else
  chown "$TARGET_UID:$TARGET_GID" "$INSTALL_DIR" "$BACKEND_PATH" "$MOUNT_PATH"
fi

############################################
# DOWNLOAD COMPOSE FILES
############################################
banner "Docker Compose Files"

cd "$INSTALL_DIR"
curl -fsSL "$MEDIA_COMPOSE_URL" -o docker-compose.media.yml
curl -fsSL "$RIVEN_COMPOSE_URL" -o docker-compose.yml
ok "Compose files downloaded"

############################################
# WSL COMPOSE OVERRIDE
############################################
USE_WSL_OVERRIDE=false

if [[ "$IS_WSL" == true ]]; then
  cat > docker-compose.wsl.override.yml <<EOF
services:
  riven:
    volumes:
      - "$BACKEND_PATH:/mnt/riven/backend"
      - "$MOUNT_PATH:/mnt/riven/mount"
EOF
  USE_WSL_OVERRIDE=true
  ok "WSL compose override enabled"
fi

############################################
# MEDIA SERVER SELECTION
############################################
banner "Media Server Selection"

echo "1) Jellyfin"
echo "2) Plex"
echo "3) Emby"
read -rp "Select: " MEDIA_SEL

case "$MEDIA_SEL" in
  1) MEDIA_PROFILE="jellyfin"; MEDIA_PORT=8096 ;;
  2) MEDIA_PROFILE="plex";     MEDIA_PORT=32400 ;;
  3) MEDIA_PROFILE="emby";     MEDIA_PORT=8097 ;;
  *) fail "Invalid selection" ;;
esac

############################################
# START MEDIA SERVER
############################################
banner "Starting Media Server"

compose -f docker-compose.media.yml --profile "$MEDIA_PROFILE" up -d
ok "Media server started"

SERVER_IP="$(hostname -I | awk '{print $1}')"
echo "Open: http://$SERVER_IP:$MEDIA_PORT"
read -rp "Press ENTER when ready..."

############################################
# MEDIA AUTH
############################################
banner "Media Authentication"
MEDIA_API_KEY="$(require_non_empty "Enter API Key / Token")"

############################################
# FRONTEND ORIGIN
############################################
banner "Frontend Origin"

ORIGIN="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " yn
[[ "${yn,,}" == "y" ]] && ORIGIN="$(require_url "Public URL")"

############################################
# SECRETS
############################################
POSTGRES_PASSWORD="$(openssl rand -hex 24)"
AUTH_SECRET="$(openssl rand -base64 32)"
BACKEND_API_KEY="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"

############################################
# .env GENERATION (HONEST PERMISSIONS)
############################################
banner ".env Generation"

cat > .env <<EOF
TZ=""
ORIGIN="$ORIGIN"
MEDIA_PROFILE="$MEDIA_PROFILE"

POSTGRES_DB="riven"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

BACKEND_API_KEY="$BACKEND_API_KEY"
AUTH_SECRET="$AUTH_SECRET"

RIVEN_UPDATERS_LIBRARY_PATH="$BACKEND_PATH"
EOF

if [[ "$IS_WSL" == true ]]; then
  warn ".env permissions controlled by Windows (WSL)"
  ok   ".env stored in Linux filesystem: $INSTALL_DIR/.env"
else
  chmod 600 .env
  ok ".env permissions set to 600"
fi

############################################
# START RIVEN
############################################
banner "Starting Riven"

if [[ "$USE_WSL_OVERRIDE" == true ]]; then
  compose -f docker-compose.yml -f docker-compose.wsl.override.yml up -d
else
  compose -f docker-compose.yml up -d
fi

############################################
# FINAL SUMMARY
############################################
banner "INSTALL COMPLETE"

ok "Environment:     $([[ "$IS_WSL" == true ]] && echo 'WSL' || echo 'Native Ubuntu')"
ok "Config path:     $INSTALL_DIR"
ok "Backend path:    $BACKEND_PATH"
ok "Mount path:      $MOUNT_PATH"
ok "Riven is running 🚀"
