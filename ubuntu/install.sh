#!/usr/bin/env bash
set -euo pipefail

############################################
# CONSTANTS
############################################
INSTALL_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"
DEFAULT_ORIGIN="http://localhost:3000"
LIBRARY_PATH="/mnt/riven/backend"

############################################
# HELPERS
############################################
banner(){ echo -e "\n========================================\n $1\n========================================"; }
ok(){ echo "[✔] $1"; }
warn(){ echo "[!] $1"; }
fail(){ echo "[✖] $1"; exit 1; }

require_non_empty() {
  local prompt="$1" value
  while true; do
    read -rsp "$prompt: " value; echo
    [[ -n "$value" ]] && { echo "$value"; return; }
    warn "Value required"
  done
}

require_url() {
  local prompt="$1" value
  local regex='^https?://([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|localhost|([0-9]{1,3}\.){3}[0-9]{1,3})(:[0-9]{1,5})?(/.*)?$'
  while true; do
    read -rp "$prompt: " value
    [[ "$value" =~ $regex ]] && { echo "$value"; return; }
    warn "Invalid URL"
  done
}

wait_for_url() {
  local name="$1" url="$2" max="${3:-300}" waited=0
  banner "Waiting for $name"
  until curl -fs "$url" >/dev/null; do
    sleep 5
    waited=$((waited+5))
    [[ "$waited" -ge "$max" ]] && fail "$name not reachable"
  done
  ok "$name reachable"
}

############################################
# ARG MODE
############################################
MODE="${1:-install}"
[[ "$MODE" == "install" || "$MODE" == "--update" ]] || fail "Usage: install.sh [--update]"

############################################
# UPDATE MODE (PROFILE SAFE)
############################################
if [[ "$MODE" == "--update" ]]; then
  cd "$INSTALL_DIR" || fail "Missing install dir"
  MEDIA_PROFILE="$(grep '^MEDIA_PROFILE=' .env | cut -d= -f2- || true)"

  banner "Update Mode"

  if [[ -n "$MEDIA_PROFILE" ]]; then
    docker compose --profile "$MEDIA_PROFILE" up -d "$MEDIA_PROFILE"
    docker compose --profile "$MEDIA_PROFILE" pull
    docker compose --profile "$MEDIA_PROFILE" up -d
  else
    docker compose pull
    docker compose up -d
  fi

  ok "Update complete"
  exit 0
fi

############################################
# PRECHECKS
############################################
[ "$(id -u)" -eq 0 ] || fail "Run with sudo"
. /etc/os-release
[[ "${ID}" == "ubuntu" ]] || fail "Ubuntu required"

############################################
# TIMEZONE
############################################
banner "Timezone"
TZ_DETECTED="$(timedatectl show --property=Timezone --value || echo UTC)"
read -rp "Timezone [$TZ_DETECTED]: " TZ_INPUT
TZ_SELECTED="${TZ_INPUT:-$TZ_DETECTED}"
timedatectl set-timezone "$TZ_SELECTED"

############################################
# SYSTEM DEPENDENCIES
############################################
banner "System Dependencies"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl fuse3

############################################
# DOCKER
############################################
banner "Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
fi

############################################
# FILESYSTEM
############################################
banner "Filesystem"
mkdir -p /mnt/riven/{backend,mount} "$INSTALL_DIR"
chown -R "${SUDO_USER:-1000}:${SUDO_USER:-1000}" /mnt/riven

############################################
# DOWNLOAD COMPOSE
############################################
banner "Docker Compose"
cd "$INSTALL_DIR"
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml

############################################
# =============================
# PHASE 1 — USER INPUT ONLY
# =============================
############################################

############################################
# MEDIA SERVER (REQUIRED)
############################################
banner "Media Server Selection (REQUIRED)"
echo "1) Jellyfin"
echo "2) Plex"
echo "3) Emby"
read -rp "Select ONE: " MEDIA_SEL

case "$MEDIA_SEL" in
  1) MEDIA_PROFILE="jellyfin"; MEDIA_URL="http://localhost:8096" ;;
  2) MEDIA_PROFILE="plex"; MEDIA_URL="http://localhost:32400" ;;
  3) MEDIA_PROFILE="emby"; MEDIA_URL="http://localhost:8097" ;;
  *) fail "Media server REQUIRED" ;;
esac

############################################
# START MEDIA ONLY
############################################
docker compose --profile "$MEDIA_PROFILE" up -d "$MEDIA_PROFILE"
wait_for_url "$MEDIA_PROFILE" "$MEDIA_URL"

banner "Finish media setup, then press ENTER"
read -r _

case "$MEDIA_PROFILE" in
  jellyfin) MEDIA_API_KEY="$(require_non_empty 'Jellyfin API Key')" ;;
  plex) MEDIA_API_KEY="$(require_non_empty 'Plex Token')" ;;
  emby) MEDIA_API_KEY="$(require_non_empty 'Emby API Key')" ;;
esac

############################################
# DOWNLOADER (REQUIRED)
############################################
banner "Downloader Selection (REQUIRED)"
echo "1) Real-Debrid"
echo "2) All-Debrid"
echo "3) Debrid-Link"
read -rp "Select ONE: " DL

case "$DL" in
  1) DL_TYPE="REAL_DEBRID"; DL_KEY="$(require_non_empty 'Real-Debrid API Key')" ;;
  2) DL_TYPE="ALL_DEBRID"; DL_KEY="$(require_non_empty 'All-Debrid API Key')" ;;
  3) DL_TYPE="DEBRID_LINK"; DL_KEY="$(require_non_empty 'Debrid-Link API Key')" ;;
  *) fail "Downloader REQUIRED" ;;
esac

############################################
# SCRAPER (REQUIRED)
############################################
banner "Scraper Selection (REQUIRED)"
echo "1) Torrentio"
echo "2) Prowlarr"
read -rp "Select ONE: " SC

case "$SC" in
  1) SCRAPER="TORRENTIO" ;;
  2)
     SCRAPER="PROWLARR"
     PROWLARR_URL="$(require_url 'Prowlarr URL')"
     PROWLARR_KEY="$(require_non_empty 'Prowlarr API Key')"
     ;;
  *) fail "Scraper REQUIRED" ;;
esac

############################################
# FRONTEND ORIGIN
############################################
banner "Frontend Origin"
ORIGIN="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " USE_PROXY
[[ "${USE_PROXY,,}" == "y" ]] && ORIGIN="$(require_url 'Public frontend URL')"

############################################
# =============================
# PHASE 2 — WRITE .env ONCE
# =============================
############################################
banner ".env Generation"

cat > .env <<EOF
TZ=$TZ_SELECTED
ORIGIN=$ORIGIN
MEDIA_PROFILE=$MEDIA_PROFILE

POSTGRES_DB=riven
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 24)
BACKEND_API_KEY=$(openssl rand -hex 32)
AUTH_SECRET=$(openssl rand -hex 32)

RIVEN_UPDATERS_LIBRARY_PATH=$LIBRARY_PATH
RIVEN_UPDATERS_UPDATER_INTERVAL=120

RIVEN_UPDATERS_JELLYFIN_ENABLED=false
RIVEN_UPDATERS_JELLYFIN_API_KEY=
RIVEN_UPDATERS_JELLYFIN_URL=http://jellyfin:8096

RIVEN_UPDATERS_PLEX_ENABLED=false
RIVEN_UPDATERS_PLEX_TOKEN=
RIVEN_UPDATERS_PLEX_URL=http://plex:32400

RIVEN_UPDATERS_EMBY_ENABLED=false
RIVEN_UPDATERS_EMBY_API_KEY=
RIVEN_UPDATERS_EMBY_URL=http://emby:8097

RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=

RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=

RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=false
RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=

RIVEN_SCRAPING_TORRENTIO_ENABLED=false
RIVEN_SCRAPING_PROWLARR_ENABLED=false
RIVEN_SCRAPING_PROWLARR_URL=
RIVEN_SCRAPING_PROWLARR_API_KEY=
EOF

############################################
# ENABLE SELECTED OPTIONS
############################################
case "$MEDIA_PROFILE" in
  jellyfin)
    sed -i "s/RIVEN_UPDATERS_JELLYFIN_ENABLED=false/RIVEN_UPDATERS_JELLYFIN_ENABLED=true/" .env
    sed -i "s|RIVEN_UPDATERS_JELLYFIN_API_KEY=.*|RIVEN_UPDATERS_JELLYFIN_API_KEY=$MEDIA_API_KEY|" .env
    ;;
  plex)
    sed -i "s/RIVEN_UPDATERS_PLEX_ENABLED=false/RIVEN_UPDATERS_PLEX_ENABLED=true/" .env
    sed -i "s|RIVEN_UPDATERS_PLEX_TOKEN=.*|RIVEN_UPDATERS_PLEX_TOKEN=$MEDIA_API_KEY|" .env
    ;;
  emby)
    sed -i "s/RIVEN_UPDATERS_EMBY_ENABLED=false/RIVEN_UPDATERS_EMBY_ENABLED=true/" .env
    sed -i "s|RIVEN_UPDATERS_EMBY_API_KEY=.*|RIVEN_UPDATERS_EMBY_API_KEY=$MEDIA_API_KEY|" .env
    ;;
esac

case "$DL_TYPE" in
  REAL_DEBRID)
    sed -i "s/RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=false/RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=true/" .env
    sed -i "s|RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=.*|RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=$DL_KEY|" .env
    ;;
  ALL_DEBRID)
    sed -i "s/RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=false/RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=true/" .env
    sed -i "s|RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=.*|RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=$DL_KEY|" .env
    ;;
  DEBRID_LINK)
    sed -i "s/RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=false/RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=true/" .env
    sed -i "s|RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=.*|RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=$DL_KEY|" .env
    ;;
esac

if [[ "$SCRAPER" == "TORRENTIO" ]]; then
  sed -i "s/RIVEN_SCRAPING_TORRENTIO_ENABLED=false/RIVEN_SCRAPING_TORRENTIO_ENABLED=true/" .env
else
  sed -i "s/RIVEN_SCRAPING_PROWLARR_ENABLED=false/RIVEN_SCRAPING_PROWLARR_ENABLED=true/" .env
  sed -i "s|RIVEN_SCRAPING_PROWLARR_URL=.*|RIVEN_SCRAPING_PROWLARR_URL=$PROWLARR_URL|" .env
  sed -i "s|RIVEN_SCRAPING_PROWLARR_API_KEY=.*|RIVEN_SCRAPING_PROWLARR_API_KEY=$PROWLARR_KEY|" .env
fi

############################################
# =============================
# PHASE 3 — START RIVEN
# =============================
############################################
banner "Starting Riven Stack"
docker compose pull
docker compose up -d riven-db riven riven-frontend

banner "INSTALL COMPLETE"
ok "Frontend: http://localhost:3000"
ok "Backend:  http://localhost:8080"
