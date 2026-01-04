#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG =====
DOWNLOAD_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"
ENV_FILE=".env"

# ===== OUTPUT =====
log()  { echo "[✔] $1"; }
step() { echo "▶ $1"; }
err()  { echo "[✖] $1"; exit 1; }

# ===== PRECHECK =====
[[ $EUID -eq 0 ]] || err "Run as root"
. /etc/os-release || err "Cannot detect OS"
[[ "$ID" == "ubuntu" ]] || err "Ubuntu required"

# ===== TIMEZONE (AUTO, NO PROMPTS) =====
step "Detecting timezone"
TZ_SELECTED="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
timedatectl set-timezone "$TZ_SELECTED"
log "Timezone set to $TZ_SELECTED"

# ===== ENSURE CURL =====
if ! command -v curl >/dev/null 2>&1; then
  step "Installing curl"
  apt-get update
  apt-get install -y curl ca-certificates
fi

# ===== ENSURE DOCKER =====
if ! command -v docker >/dev/null 2>&1; then
  step "Installing Docker"
  apt-get update
  apt-get install -y ca-certificates gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
> /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
fi

# ===== SETUP DIR =====
step "Preparing directory"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# ===== DOWNLOAD COMPOSE =====
step "Downloading docker-compose.yml"
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml || err "Compose download failed"

# ===== GENERATE .ENV =====
if [[ ! -f "$ENV_FILE" ]]; then
  step "Generating .env"

  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  BACKEND_API_KEY="$(openssl rand -hex 32)"
  AUTH_SECRET="$(openssl rand -hex 32)"

  printf "TZ=%s\n\nPOSTGRES_DB=riven\nPOSTGRES_USER=postgres\nPOSTGRES_PASSWORD=%s\n\nBACKEND_API_KEY=%s\nAUTH_SECRET=%s\n" \
    "$TZ_SELECTED" \
    "$POSTGRES_PASSWORD" \
    "$BACKEND_API_KEY" \
    "$AUTH_SECRET" > "$ENV_FILE"

  log ".env created"
fi

# ===== MOUNTS =====
step "Creating mount paths"
mkdir -p /mnt/riven/backend /mnt/riven/mount
chown -R 1000:1000 /mnt/riven

# ===== SYSTEMD SERVICE =====
step "Creating mount service"

printf "[Unit]
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
" > /etc/systemd/system/riven-bind-shared.service

systemctl daemon-reload
systemctl enable --now riven-bind-shared.service

# ===== START STACK =====
step "Starting Docker"
systemctl start docker

step "Starting containers"
docker compose pull
docker compose up -d

log "Riven install complete"
log "Compose: $DOWNLOAD_DIR/docker-compose.yml"
log "Env: $DOWNLOAD_DIR/.env"
