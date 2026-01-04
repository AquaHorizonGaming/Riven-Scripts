#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
DOWNLOAD_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"
ENV_FILE=".env"

############################################
# OUTPUT
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
# COMMAND DETECTION (NO APT UNLESS NEEDED)
############################################
REQUIRED_CMDS=(
  curl
  openssl
  gpg
  lsb_release
)

MISSING_CMDS=()

for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING_CMDS+=("$cmd")
  fi
done

if (( ${#MISSING_CMDS[@]} > 0 )); then
  step "Installing missing system commands: ${MISSING_CMDS[*]}"
  apt-get update
  apt-get install -y \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    openssl
else
  log "All required system commands detected — skipping apt"
fi

############################################
# TIMEZONE (NON-INTERACTIVE SAFE)
############################################
step "Detecting timezone"

DEFAULT_TZ="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
DEFAULT_TZ="${DEFAULT_TZ:-UTC}"

if [[ ! -t 0 ]]; then
  TZ_SELECTED="$DEFAULT_TZ"
  log "Non-interactive install — using timezone: $TZ_SELECTED"
else
  echo
  echo -e "Detected timezone: ${GREEN}$DEFAULT_TZ${NC}"
  read -rp "Press ENTER to accept or type another: " USER_TZ
  TZ_SELECTED="${USER_TZ:-$DEFAULT_TZ}"
fi

timedatectl set-timezone "$TZ_SELECTED"
log "Timezone set to $TZ_SELECTED"

############################################
# DOWNLOAD DIRECTORY
############################################
step "Preparing download directory"

mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

############################################
# DOWNLOAD COMPOSE
############################################
step "Downloading docker-compose.yml"

curl -fsSL "$COMPOSE_URL" -o docker-compose.yml \
  || err "Failed to download docker-compose.yml"

############################################
# ENV AUTO-GEN
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
# DOCKER DETECTION + INSTALL
############################################
step "Checking Docker"

if ! command -v docker >/dev/null 2>&1; then
  step "Installing Docker"

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
# MOUNTS
############################################
step "Creating mount directories"

mkdir -p /mnt/riven/backend /mnt/riven/mount /mnt/jellyfin /mnt/plex /mnt/emby
chown -R 1000:1000 /mnt/riven /mnt/jellyfin /mnt/plex /mnt/emby

############################################
# SYSTEMD SHARED MOUNT
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
# START STACK
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
log "Timezone: $TZ_SELECTED"
log "Compose: $DOWNLOAD_DIR/docker-compose.yml"
log "Env: $DOWNLOAD_DIR/.env"
