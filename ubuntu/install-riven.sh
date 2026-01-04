#!/usr/bin/env bash
set -euo pipefail

############################################
# USER CONFIG (EDIT THESE)
############################################
DOWNLOAD_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/refs/heads/main/ubuntu/docker-compose.yml"
ENV_FILE=".env"

############################################
# COLORS / OUTPUT
############################################
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

log()  { echo -e "${GREEN}[✔]${NC} $1"; }
step() { echo -e "${BLUE}▶${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✖]${NC} $1"; exit 1; }

############################################
# PRECHECKS
############################################
[[ $EUID -eq 0 ]] || err "Run as root (sudo)"
[[ "$(uname -s)" == "Linux" ]] || err "Linux required"

. /etc/os-release || err "Cannot detect OS"
[[ "$ID" == "ubuntu" ]] || err "Ubuntu required"

############################################
# BASE DEPS
############################################
step "Installing base dependencies (curl, ca-certificates, gnupg)"

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  openssl

############################################
# TIMEZONE
############################################
step "Detecting timezone"

DEFAULT_TZ="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
DEFAULT_TZ="${DEFAULT_TZ:-UTC}"

echo
echo -e "Detected timezone: ${GREEN}$DEFAULT_TZ${NC}"
read -rp "Press ENTER to accept or type another (e.g. America/New_York): " USER_TZ
TZ_SELECTED="${USER_TZ:-$DEFAULT_TZ}"

timedatectl list-timezones | grep -qx "$TZ_SELECTED" || err "Invalid timezone"
timedatectl set-timezone "$TZ_SELECTED"
log "Timezone set to $TZ_SELECTED"

############################################
# DIRECTORY SETUP
############################################
step "Preparing download directory"

mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

############################################
# DOWNLOAD FILES
############################################
step "Downloading docker-compose.yml"

curl -fsSL "$COMPOSE_URL" -o docker-compose.yml || err "Failed to download compose file"

############################################
# ENV GENERATION
############################################
if [[ ! -f "$ENV_FILE" ]]; then
  step "Generating .env"

  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  BACKEND_API_KEY="$(openssl rand -hex 32)"
  AUTH_SECRET="$(openssl rand -hex 32)"

  cat > "$ENV_FILE" <<EOF
TZ=$TZ_SELECTED

POSTGRES_DB=riven
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

BACKEND_API_KEY=$BACKEND_API_KEY
AUTH_SECRET=$AUTH_SECRET
EOF

  warn "SAVE $DOWNLOAD_DIR/.env — it contains secrets"
else
  log ".env already exists — leaving unchanged"
fi

############################################
# DOCKER INSTALL
############################################
step "Installing Docker if missing"

if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
else
  log "Docker already installed"
fi

############################################
# MOUNT DIRECTORIES
############################################
step "Creating mount directories"

mkdir -p /mnt/riven/backend /mnt/riven/mount /mnt/jellyfin /mnt/plex /mnt/emby
chown -R 1000:1000 /mnt/riven /mnt/jellyfin /mnt/plex /mnt/emby

############################################
# SYSTEMD MOUNT SERVICE
############################################
step "Configuring shared mount systemd service"

cat > /etc/systemd/system/riven-bind-shared.service <<EOF
[Unit]
Description=Make Riven mount bind shared
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --bind /mnt/riven/mount /mnt/riven/mount
ExecStart=/usr/bin/mount --make-rshared /mnt/riven/mount
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now riven-bind-shared.service

############################################
# VERIFY MOUNT
############################################
step "Verifying mount propagation"

findmnt -T /mnt/riven/mount -o PROPAGATION | grep -q shared \
  || err "Mount is NOT shared"

############################################
# START DOCKER + STACK
############################################
step "Starting Docker"
systemctl start docker

step "Starting Riven stack"
docker compose pull
docker compose up -d

############################################
# DONE
############################################
log "Riven installed successfully"
log "Compose location: $DOWNLOAD_DIR/docker-compose.yml"
log "Env file: $DOWNLOAD_DIR/.env"
log "Timezone: $TZ_SELECTED"
