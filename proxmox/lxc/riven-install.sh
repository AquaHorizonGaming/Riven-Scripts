#!/usr/bin/env bash
set -euo pipefail

echo "== Riven Docker Install (inside LXC) =="

ROOT_DIR="/srv/riven"
INSTALL_DIR="$ROOT_DIR/app"
DATA_DIR="$ROOT_DIR/data"
BACKEND_DIR="$ROOT_DIR/backend"
MOUNT_DIR="$ROOT_DIR/mount"
MEDIA_DIR="$ROOT_DIR/media"

RIVEN_UID=1000
RIVEN_GID=1000

# ----------------------------
# Directory setup
# ----------------------------
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BACKEND_DIR" "$MOUNT_DIR"
mkdir -p "$MEDIA_DIR/jellyfin" "$MEDIA_DIR/plex" "$MEDIA_DIR/emby"
chown -R "$RIVEN_UID:$RIVEN_GID" "$ROOT_DIR"

# ----------------------------
# Ensure bind + rshared mount
# ----------------------------
if ! mountpoint -q "$MOUNT_DIR"; then
  mount --bind "$MOUNT_DIR" "$MOUNT_DIR"
fi

mount --make-rshared "$MOUNT_DIR"

PROP="$(findmnt -T "$MOUNT_DIR" -o PROPAGATION -n || true)"
if [[ "$PROP" != "shared" && "$PROP" != "rshared" ]]; then
  echo "ERROR: $MOUNT_DIR is not shared (got: $PROP)"
  exit 1
fi

# ----------------------------
# Persist rshared mount on boot
# ----------------------------
cat >/etc/systemd/system/riven-bind-shared.service <<EOF
[Unit]
Description=Make Riven mount bind shared
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --bind "$MOUNT_DIR" "$MOUNT_DIR"
ExecStart=/usr/bin/mount --make-rshared "$MOUNT_DIR"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now riven-bind-shared.service

# ----------------------------
# Install location
# ----------------------------
cd "$INSTALL_DIR"

# ----------------------------
# Generate secrets (.env) once
# ----------------------------
if [[ ! -f .env ]]; then
  POSTGRES_DB="riven"
  POSTGRES_USER="riven_$(openssl rand -hex 4)"
  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  BACKEND_API_KEY="$(openssl rand -hex 16)"  # 32 chars
  AUTH_SECRET="$(openssl rand -base64 32)"
  TZ="$(cat /etc/timezone 2>/dev/null || echo UTC)"

  cat > .env <<EOF
TZ=$TZ
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
BACKEND_API_KEY=$BACKEND_API_KEY
AUTH_SECRET=$AUTH_SECRET
DATABASE_URL=/riven/data/riven.db
BACKEND_URL=http://riven:8080
EOF
fi

# ----------------------------
# Validate required files
# ----------------------------
[[ -f /root/docker-compose.yml ]] || {
  echo "ERROR: /root/docker-compose.yml not found (pct push failed?)"
  exit 1
}

[[ -f /root/upgrade.sh ]] || {
  echo "ERROR: /root/upgrade.sh not found (pct push failed?)"
  exit 1
}

# ----------------------------
# Install compose + upgrade
# ----------------------------
cp /root/docker-compose.yml "$INSTALL_DIR/docker-compose.yml"
cp /root/upgrade.sh "$INSTALL_DIR/upgrade.sh"
chmod +x "$INSTALL_DIR/upgrade.sh"

# ----------------------------
# Start containers
# ----------------------------
echo "Starting containers..."
docker compose up -d

# ----------------------------
# Print credentials + warnings
# ----------------------------
POSTGRES_DB="$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)"
POSTGRES_USER="$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)"
POSTGRES_PASSWORD="$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Riven stack deployed inside LXC"
echo
echo "📦 PostgreSQL credentials (SAVE THESE):"
echo "  Database : $POSTGRES_DB"
echo "  User     : $POSTGRES_USER"
echo "  Password : $POSTGRES_PASSWORD"
echo
echo "🚨 REQUIRED CONFIGURATION 🚨"
echo "⚠️  YOU MUST CONFIGURE A MEDIA SERVER OR RIVEN WONT START"
echo
echo "Edit:"
echo "  $BACKEND_DIR/settings.json"
echo
echo "After configuring, restart:"
echo "  docker restart riven"
echo
echo "Optional media servers:"
echo "  docker compose --profile jellyfin up -d"
echo "  docker compose --profile plex up -d"
echo "  docker compose --profile emby up -d"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
