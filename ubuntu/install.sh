#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
INSTALL_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"
FRONTEND_PORT="3000"
DEFAULT_ORIGIN="http://localhost:3000"

############################################
# OUTPUT HELPERS
############################################
banner() {
  echo
  echo "========================================"
  echo " $1"
  echo "========================================"
}
ok()   { echo "[✔] $1"; }
warn() { echo "[!] $1"; }
fail() { echo "[✖] $1"; exit 1; }

############################################
# URL VALIDATION
############################################
is_valid_url() {
  [[ "$1" =~ ^https?:// ]]
}

############################################
# PRECHECKS
############################################
[ "$(id -u)" -eq 0 ] || fail "Run this script as root (sudo)"
. /etc/os-release || fail "Cannot detect OS"
[ "$ID" = "ubuntu" ] || fail "Ubuntu is required"

############################################
# TIMEZONE
############################################
banner "Timezone Configuration"

TZ_DETECTED="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
echo "Detected timezone: $TZ_DETECTED"

if [ -t 0 ]; then
  read -rp "Press ENTER to accept or type another (e.g. America/New_York): " TZ_INPUT
  TZ_SELECTED="${TZ_INPUT:-$TZ_DETECTED}"
else
  TZ_SELECTED="$TZ_DETECTED"
fi

timedatectl set-timezone "$TZ_SELECTED"
ok "Timezone set to $TZ_SELECTED"

############################################
# DEPENDENCIES
############################################
banner "Dependency Check"

REQUIRED_CMDS=(curl openssl gpg)
MISSING=()

for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" >/dev/null || MISSING+=("$cmd")
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  warn "Installing missing packages: ${MISSING[*]}"
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release openssl
else
  ok "All required system commands detected — skipping apt"
fi

############################################
# DOCKER
############################################
banner "Docker Installation"

if ! command -v docker >/dev/null; then
  warn "Docker not detected — installing"

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
else
  ok "Docker already installed"
fi

############################################
# DOCKER IPv4 ONLY
############################################
banner "Docker IPv4 Configuration"

mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<EOF
{
  "ipv6": false,
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

systemctl restart docker
ok "Docker configured for IPv4 only"

############################################
# FILESYSTEM
############################################
banner "Filesystem Setup"

mkdir -p \
  /mnt/riven/backend \
  /mnt/riven/mount \
  "$INSTALL_DIR"

chown -R 1000:1000 /mnt/riven || true

ok "Backend path: /mnt/riven/backend"
ok "Mount path:   /mnt/riven/mount"
ok "Install dir:  $INSTALL_DIR"

############################################
# MOUNT PROPAGATION
############################################
banner "Mount Propagation (rshared)"

cat >/etc/systemd/system/riven-bind-shared.service <<EOF
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
ok "Mount propagation enabled"

############################################
# ORIGIN / REVERSE PROXY
############################################
banner "Frontend Origin Configuration"

ORIGIN_SELECTED="$DEFAULT_ORIGIN"

if [ -t 0 ]; then
  read -rp "Are you using a reverse proxy? (y/N): " USE_PROXY
  USE_PROXY="${USE_PROXY,,}"

  if [[ "$USE_PROXY" == "y" || "$USE_PROXY" == "yes" ]]; then
    while true; do
      read -rp "Enter public frontend URL (http:// or https://): " ORIGIN_INPUT
      if is_valid_url "$ORIGIN_INPUT"; then
        ORIGIN_SELECTED="$ORIGIN_INPUT"
        break
      else
        warn "Invalid URL — must start with http:// or https://"
      fi
    done
  fi
else
  warn "Non-interactive shell — defaulting ORIGIN"
fi

ok "ORIGIN set to: $ORIGIN_SELECTED"

############################################
# RIVEN DEPLOYMENT
############################################
banner "Riven Deployment"

cd "$INSTALL_DIR"
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml || fail "Failed to download docker-compose.yml"
ok "docker-compose.yml downloaded"

if [ ! -f .env ]; then
  warn ".env not found — generating one (SAVE THIS FILE)"
  cat > .env <<EOF
TZ=$TZ_SELECTED
ORIGIN=$ORIGIN_SELECTED
POSTGRES_DB=riven
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 24)
BACKEND_API_KEY=$(openssl rand -hex 32)
AUTH_SECRET=$(openssl rand -hex 32)
EOF
else
  ok ".env already exists — keeping it"
fi

docker compose pull
docker compose up -d

############################################
# HEALTH CHECK
############################################
banner "Container Health Check"

EXPECTED_CONTAINERS=(
  riven-db
  riven
  riven-frontend
)

sleep 5

for c in "${EXPECTED_CONTAINERS[@]}"; do
  if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
    warn "Container $c not running — restarting"
    docker compose up -d "$c" || warn "Failed to start $c"
  else
    ok "$c is running"
  fi
done

############################################
# FINAL OUTPUT
############################################
SERVER_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
[ -z "$SERVER_IP" ] && SERVER_IP="SERVER_IP"

echo
echo "⚠️  REQUIRED CONFIGURATION (DO NOT SKIP)"
echo
echo "• Edit:"
echo "  /mnt/riven/backend/settings.json"
echo
echo "• You MUST configure:"
echo "  - At least ONE scraper"
echo "  - At least ONE media server (Plex / Jellyfin / Emby)"
echo
echo "• Media output path:"
echo "  /mnt/riven/mount"
echo
echo "• Docker Compose:"
echo "  $INSTALL_DIR/docker-compose.yml"
echo
echo "• Frontend access:"
echo "  $ORIGIN_SELECTED"
echo

ok "Riven installation complete"
