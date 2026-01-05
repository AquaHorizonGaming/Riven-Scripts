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
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

wait_for_url() {
  local name="$1"
  local url="$2"
  banner "Waiting for $name"
  until curl -fs "$url" >/dev/null; do sleep 5; done
  ok "$name is online"
}

############################################
# PRECHECKS
############################################
[ "$(id -u)" -eq 0 ] || fail "Run as root"
. /etc/os-release || fail "Cannot detect OS"
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
# DEPENDENCIES + DOCKER
############################################
banner "System Setup"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl

if ! command -v docker >/dev/null; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
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
chown -R 1000:1000 /mnt/riven || true

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
  while true; do
    read -rp "Public URL (http/https): " ORIGIN
    [[ "$ORIGIN" =~ ^https?:// ]] && break
    warn "Invalid URL"
  done
fi

############################################
# DEPLOY FILES
############################################
banner "Preparing Files"
cd "$INSTALL_DIR"
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml

if [ ! -f .env ]; then
  cat > .env <<EOF
TZ=$TZ
ORIGIN=$ORIGIN
POSTGRES_DB=riven
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 24)
BACKEND_API_KEY=$(openssl rand -hex 32)
AUTH_SECRET=$(openssl rand -hex 32)
EOF
fi

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
      MEDIA_PROFILE="jellyfin"
      MEDIA_NAME="Jellyfin"
      HEALTH_URL="http://localhost:8096"
      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED true
      set_env RIVEN_UPDATERS_JELLYFIN_URL http://jellyfin:8096
      set_env RIVEN_UPDATERS_PLEX_ENABLED false
      set_env RIVEN_UPDATERS_EMBY_ENABLED false
      read -rsp "Jellyfin API Key: " KEY; echo
      set_env RIVEN_UPDATERS_JELLYFIN_API_KEY "$KEY"
      break
      ;;
    2)
      MEDIA_PROFILE="plex"
      MEDIA_NAME="Plex"
      HEALTH_URL="http://localhost:32400/web"
      set_env RIVEN_UPDATERS_PLEX_ENABLED true
      set_env RIVEN_UPDATERS_PLEX_URL http://plex:32400
      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED false
      set_env RIVEN_UPDATERS_EMBY_ENABLED false
      read -rsp "Plex Token: " KEY; echo
      set_env RIVEN_UPDATERS_PLEX_TOKEN "$KEY"
      break
      ;;
    3)
      MEDIA_PROFILE="emby"
      MEDIA_NAME="Emby"
      HEALTH_URL="http://localhost:8097"
      set_env RIVEN_UPDATERS_EMBY_ENABLED true
      set_env RIVEN_UPDATERS_EMBY_URL http://emby:8097
      set_env RIVEN_UPDATERS_PLEX_ENABLED false
      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED false
      read -rsp "Emby API Key: " KEY; echo
      set_env RIVEN_UPDATERS_EMBY_API_KEY "$KEY"
      break
      ;;
    *) warn "Media server is REQUIRED";;
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

  set_env RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED false
  set_env RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED false
  set_env RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED false

  for d in $DL; do
    case "$d" in
      1) read -rsp "Real-Debrid API Key: " K; echo; set_env RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY "$K"; set_env RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED true; DL_OK=true;;
      2) read -rsp "All-Debrid API Key: " K; echo; set_env RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY "$K"; set_env RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED true; DL_OK=true;;
      3) read -rsp "Debrid-Link API Key: " K; echo; set_env RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY "$K"; set_env RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED true; DL_OK=true;;
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

  for s in TORRENTIO PROWLARR ZILEAN COMET JACKETT ORIONOID RARBG; do
    set_env RIVEN_SCRAPING_${s}_ENABLED false
  done

  for s in $SC; do
    case "$s" in
      1) set_env RIVEN_SCRAPING_TORRENTIO_ENABLED true; SC_OK=true;;
      2) read -rp "Prowlarr URL: " U; read -rsp "Prowlarr API Key: " K; echo; set_env RIVEN_SCRAPING_PROWLARR_URL "$U"; set_env RIVEN_SCRAPING_PROWLARR_API_KEY "$K"; set_env RIVEN_SCRAPING_PROWLARR_ENABLED true; SC_OK=true;;
      3) read -rp "Zilean URL: " U; set_env RIVEN_SCRAPING_ZILEAN_URL "$U"; set_env RIVEN_SCRAPING_ZILEAN_ENABLED true; SC_OK=true;;
      4) read -rp "Comet URL: " U; set_env RIVEN_SCRAPING_COMET_URL "$U"; set_env RIVEN_SCRAPING_COMET_ENABLED true; SC_OK=true;;
      5) read -rp "Jackett URL: " U; read -rsp "Jackett API Key: " K; echo; set_env RIVEN_SCRAPING_JACKETT_URL "$U"; set_env RIVEN_SCRAPING_JACKETT_API_KEY "$K"; set_env RIVEN_SCRAPING_JACKETT_ENABLED true; SC_OK=true;;
    esac
  done
  $SC_OK || warn "Scraper REQUIRED"
done

############################################
# GLOBAL SCRAPER DEFAULTS
############################################
set_env RIVEN_SCRAPING_DUBBED_ANIME_ONLY true
set_env RIVEN_SCRAPING_MAX_FAILED_ATTEMPTS 0
set_env RIVEN_SCRAPING_BUCKET_LIMIT 5
set_env RIVEN_SCRAPING_ENABLE_ALIASES true

############################################
# START STACK (ORDERED)
############################################
banner "Starting Media Server"
docker compose --profile "$MEDIA_PROFILE" up -d
wait_for_url "$MEDIA_NAME" "$HEALTH_URL"

banner "Starting Riven"
docker compose pull
docker compose up -d riven-db riven riven-frontend

############################################
# DONE
############################################
banner "Install Complete"
ok "Riven is fully configured and running"
