#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
INSTALL_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"
DEFAULT_ORIGIN="http://localhost:3000"

############################################
# HELPERS
############################################
banner(){ echo -e "\n========================================\n $1\n========================================"; }
ok(){ echo "[✔] $1"; }
warn(){ echo "[!] $1"; }
fail(){ echo "[✖] $1"; exit 1; }

set_env() {
  local key="$1" value="$2"
  grep -q "^$key=" .env 2>/dev/null \
    && sed -i "s|^$key=.*|$key=$value|" .env \
    || echo "$key=$value" >> .env
}

wait_for_url() {
  local name="$1" url="$2" max=60 count=0
  banner "Waiting for $name"
  until curl -fs "$url" >/dev/null; do
    sleep 5
    count=$((count+1))
    [ "$count" -ge "$max" ] && fail "$name failed to start after 5 minutes"
  done
  ok "$name is online"
}

require_non_empty() {
  local prompt="$1" value
  while true; do
    read -rsp "$prompt: " value; echo
    [ -n "$value" ] && { echo "$value"; return; }
    warn "Value cannot be empty"
  done
}

require_url() {
  local prompt="$1" value
  while true; do
    read -rp "$prompt: " value
    [[ "$value" =~ ^https?://[^[:space:]]+$ ]] && { echo "$value"; return; }
    warn "Invalid URL"
  done
}

############################################
# PRECHECKS
############################################
[ "$(id -u)" -eq 0 ] || fail "Run with sudo"
. /etc/os-release
[ "$ID" = "ubuntu" ] || fail "Ubuntu required"

############################################
# TIMEZONE
############################################
banner "Timezone"
TZ_DETECTED="$(timedatectl show --property=Timezone --value || echo UTC)"
read -rp "Timezone [$TZ_DETECTED]: " TZ_INPUT
TZ="${TZ_INPUT:-$TZ_DETECTED}"
timedatectl set-timezone "$TZ"

############################################
# SYSTEM + DOCKER
############################################
banner "System Setup"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl

if ! command -v docker >/dev/null; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-compose-plugin
  systemctl enable docker
fi

############################################
# FILESYSTEM + MOUNT
############################################
banner "Filesystem"
mkdir -p /mnt/riven/{backend,mount} "$INSTALL_DIR"

TARGET_USER="${SUDO_USER:-}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"
TARGET_GID="$(id -g "$TARGET_USER" 2>/dev/null || echo 1000)"
chown -R "$TARGET_UID:$TARGET_GID" /mnt/riven || true

cat >/etc/systemd/system/riven-bind-shared.service <<EOF
[Unit]
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
# ORIGIN
############################################
banner "Frontend Origin"
ORIGIN="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " RP
if [[ "${RP,,}" == "y" ]]; then
  ORIGIN="$(require_url "Public frontend URL")"
fi

############################################
# FILES
############################################
banner "Preparing Files"
cd "$INSTALL_DIR"
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml

cat > .env <<EOF
TZ=$TZ
ORIGIN=$ORIGIN
POSTGRES_DB=riven
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 24)
BACKEND_API_KEY=$(openssl rand -hex 32)
AUTH_SECRET=$(openssl rand -hex 32)
EOF

############################################
# MEDIA SERVER (REQUIRED)
############################################
banner "Media Server (REQUIRED)"

while true; do
  echo "1) Jellyfin"
  echo "2) Plex"
  echo "3) Emby"
  read -rp "Select ONE: " MS
  case "$MS" in
    1)
      MEDIA_PROFILE=jellyfin
      HEALTH_URL="http://localhost:8096"
      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED true
      set_env RIVEN_UPDATERS_JELLYFIN_URL http://jellyfin:8096
      KEY="$(require_non_empty "Jellyfin API Key")"
      set_env RIVEN_UPDATERS_JELLYFIN_API_KEY "$KEY"
      break;;
    2)
      MEDIA_PROFILE=plex
      HEALTH_URL="http://localhost:32400/web"
      set_env RIVEN_UPDATERS_PLEX_ENABLED true
      set_env RIVEN_UPDATERS_PLEX_URL http://plex:32400
      KEY="$(require_non_empty "Plex Token")"
      set_env RIVEN_UPDATERS_PLEX_TOKEN "$KEY"
      break;;
    3)
      MEDIA_PROFILE=emby
      HEALTH_URL="http://localhost:8097"
      set_env RIVEN_UPDATERS_EMBY_ENABLED true
      set_env RIVEN_UPDATERS_EMBY_URL http://emby:8097
      KEY="$(require_non_empty "Emby API Key")"
      set_env RIVEN_UPDATERS_EMBY_API_KEY "$KEY"
      break;;
    *) warn "Media server REQUIRED";;
  esac
done

############################################
# DOWNLOADERS (REQUIRED)
############################################
banner "Downloaders (REQUIRED)"
DL_OK=false
while ! $DL_OK; do
  echo "1) Real-Debrid"
  echo "2) All-Debrid"
  echo "3) Debrid-Link"
  read -rp "Select (space-separated): " DL
  for d in $DL; do
    case "$d" in
      1) set_env RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED true
         set_env RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY "$(require_non_empty "Real-Debrid API Key")"
         DL_OK=true;;
      2) set_env RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED true
         set_env RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY "$(require_non_empty "All-Debrid API Key")"
         DL_OK=true;;
      3) set_env RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED true
         set_env RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY "$(require_non_empty "Debrid-Link API Key")"
         DL_OK=true;;
    esac
  done
  $DL_OK || warn "Downloader REQUIRED"
done

############################################
# SCRAPERS (REQUIRED)
############################################
banner "Scrapers (REQUIRED)"
SC_OK=false
while ! $SC_OK; do
  echo "1) Torrentio"
  echo "2) Prowlarr"
  echo "3) Zilean"
  echo "4) Comet"
  echo "5) Jackett"
  read -rp "Select (space-separated): " SC
  for s in $SC; do
    case "$s" in
      1) set_env RIVEN_SCRAPING_TORRENTIO_ENABLED true; SC_OK=true;;
      2) set_env RIVEN_SCRAPING_PROWLARR_ENABLED true
         set_env RIVEN_SCRAPING_PROWLARR_URL "$(require_url "Prowlarr URL")"
         set_env RIVEN_SCRAPING_PROWLARR_API_KEY "$(require_non_empty "Prowlarr API Key")"
         SC_OK=true;;
      3) set_env RIVEN_SCRAPING_ZILEAN_ENABLED true
         set_env RIVEN_SCRAPING_ZILEAN_URL "$(require_url "Zilean URL")"
         SC_OK=true;;
      4) set_env RIVEN_SCRAPING_COMET_ENABLED true
         set_env RIVEN_SCRAPING_COMET_URL "$(require_url "Comet URL")"
         SC_OK=true;;
      5) set_env RIVEN_SCRAPING_JACKETT_ENABLED true
         set_env RIVEN_SCRAPING_JACKETT_URL "$(require_url "Jackett URL")"
         set_env RIVEN_SCRAPING_JACKETT_API_KEY "$(require_non_empty "Jackett API Key")"
         SC_OK=true;;
    esac
  done
  $SC_OK || warn "Scraper REQUIRED"
done

############################################
# START STACK
############################################
banner "Starting Media Server"
docker compose --profile "$MEDIA_PROFILE" up -d
wait_for_url "$MEDIA_PROFILE" "$HEALTH_URL"

banner "Starting Riven"
docker compose pull
docker compose up -d riven-db riven riven-frontend

banner "Install Complete"
ok "Riven is fully configured and running"
