#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
INSTALL_DIR="/opt/riven"
COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"
DEFAULT_ORIGIN="http://localhost:3000"
LIBRARY_PATH="/mnt/riven/backend"

############################################
# HELPERS
# banner prints a framed banner that displays the provided message.
banner(){ echo -e "\n========================================\n $1\n========================================"; }
# ok prints a success message prefixed with a checkmark and the provided text.
ok(){ echo "[✔] $1"; }
# warn prints a warning message prefixed with "[!]" followed by the provided text.
warn(){ echo "[!] $1"; }
# fail prints an error message prefixed with "[✖]" and exits the script with status 1.
fail(){ echo "[✖] $1"; exit 1; }

# set_env updates or appends a key=value pair in the .env file.
# key is the variable name to set; value is the value to assign. If the key exists its line is replaced, otherwise a new line is appended.
set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

# require_non_empty prompts repeatedly with the given prompt until the user provides a non-empty value, then echoes that value.
require_non_empty() {
  local prompt="$1" value
  while true; do
    read -rsp "${prompt}: " value; echo
    if [ -n "$value" ]; then
      echo "$value"
      return
    fi
    warn "Value cannot be empty"
  done
}

# Strengthened URL validation pattern (CodeRabbit request)
# - http/https
# - domain with TLD OR localhost OR IPv4
# - optional :port
# require_url prompts for a URL using the given prompt, validates that it is http:// or https:// with a hostname (including TLD), `localhost`, or IPv4 address and optional port/path, echoes the validated URL, and repeats until a valid URL is entered.
require_url() {
  local prompt="$1" value
  local regex='^https?://([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|localhost|([0-9]{1,3}\.){3}[0-9]{1,3})(:[0-9]{1,5})?(/.*)?$'
  while true; do
    read -rp "${prompt}: " value
    if [[ "$value" =~ $regex ]]; then
      echo "$value"
      return
    fi
    warn "Invalid URL (must be http(s)://host[:port][/path])"
  done
}

# wait_for_url waits for the given named URL to become reachable by polling until the optional timeout (in seconds) is reached; on timeout it fails and exits with status 1.
wait_for_url() {
  local name="$1" url="$2" max_seconds="${3:-300}"
  local waited=0
  banner "Waiting for ${name} (${url})"
  until curl -fs "$url" >/dev/null; do
    sleep 5
    waited=$((waited + 5))
    if [ "$waited" -ge "$max_seconds" ]; then
      fail "${name} failed to become reachable after ${max_seconds}s"
    fi
  done
  ok "${name} is reachable"
}

############################################
# PRECHECKS
############################################
[ "$(id -u)" -eq 0 ] || fail "Run with sudo"
. /etc/os-release || fail "Cannot detect OS"
[ "${ID:-}" = "ubuntu" ] || fail "Ubuntu is required"

############################################
# TIMEZONE
############################################
banner "Timezone"
TZ_DETECTED="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
read -rp "Timezone [${TZ_DETECTED}]: " TZ_INPUT
TZ_SELECTED="${TZ_INPUT:-$TZ_DETECTED}"
timedatectl set-timezone "$TZ_SELECTED"
ok "Timezone set: $TZ_SELECTED"

############################################
# DEPENDENCIES
############################################
banner "System Dependencies"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl

############################################
# DOCKER
############################################
banner "Docker"
if ! command -v docker >/dev/null 2>&1; then
  warn "Docker not detected — installing"
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
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
# DOCKER IPv4 ONLY (kept from your script)
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
ok "Docker configured (IPv4-only)"

############################################
# FILESYSTEM + MOUNT PROPAGATION
############################################
banner "Filesystem + Mounts"
mkdir -p /mnt/riven/{backend,mount} "$INSTALL_DIR"

TARGET_USER="${SUDO_USER:-}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"
TARGET_GID="$(id -g "$TARGET_USER" 2>/dev/null || echo 1000)"

# IMPORTANT: no "|| true" (CodeRabbit requirement) — surface permission issues
chown -R "$TARGET_UID:$TARGET_GID" /mnt/riven

ok "Backend path: /mnt/riven/backend"
ok "Mount path:   /mnt/riven/mount"
ok "Install dir:  $INSTALL_DIR"

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
banner "Frontend Origin"
ORIGIN_SELECTED="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " USE_PROXY
if [[ "${USE_PROXY,,}" == "y" ]]; then
  ORIGIN_SELECTED="$(require_url "Public frontend URL")"
fi
ok "ORIGIN=${ORIGIN_SELECTED}"

############################################
# DOWNLOAD COMPOSE
############################################
banner "Download docker-compose.yml"
cd "$INSTALL_DIR"
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml
ok "docker-compose.yml updated"

############################################
# .env SETUP (single source of truth)
############################################
banner ".env Configuration"
if [ ! -f .env ]; then
  cat > .env <<EOF
TZ=${TZ_SELECTED}
ORIGIN=${ORIGIN_SELECTED}
POSTGRES_DB=riven
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 24)
BACKEND_API_KEY=$(openssl rand -hex 32)
AUTH_SECRET=$(openssl rand -hex 32)

# =========================
# UPDATERS — CORE
# =========================
RIVEN_UPDATERS_UPDATER_INTERVAL=120
RIVEN_UPDATERS_LIBRARY_PATH=${LIBRARY_PATH}

# =========================
# UPDATERS — PLEX
# =========================
RIVEN_UPDATERS_PLEX_ENABLED=false
RIVEN_UPDATERS_PLEX_TOKEN=
RIVEN_UPDATERS_PLEX_URL=http://plex:32400

# =========================
# UPDATERS — JELLYFIN
# =========================
RIVEN_UPDATERS_JELLYFIN_ENABLED=false
RIVEN_UPDATERS_JELLYFIN_API_KEY=
RIVEN_UPDATERS_JELLYFIN_URL=http://jellyfin:8096

# =========================
# UPDATERS — EMBY
# =========================
RIVEN_UPDATERS_EMBY_ENABLED=false
RIVEN_UPDATERS_EMBY_API_KEY=
RIVEN_UPDATERS_EMBY_URL=http://emby:8097

# =========================
# SCRAPING — GLOBAL
# =========================
RIVEN_SCRAPING_DUBBED_ANIME_ONLY=true
RIVEN_SCRAPING_MAX_FAILED_ATTEMPTS=0
RIVEN_SCRAPING_BUCKET_LIMIT=5
RIVEN_SCRAPING_ENABLE_ALIASES=true

# =========================
# SCRAPING — TORRENTIO
# =========================
RIVEN_SCRAPING_TORRENTIO_ENABLED=false
RIVEN_SCRAPING_TORRENTIO_RATELIMIT=true
RIVEN_SCRAPING_TORRENTIO_PROXY_URL=

# =========================
# SCRAPING — JACKETT
# =========================
RIVEN_SCRAPING_JACKETT_ENABLED=false
RIVEN_SCRAPING_JACKETT_URL=
RIVEN_SCRAPING_JACKETT_API_KEY=

# =========================
# SCRAPING — PROWLARR
# =========================
RIVEN_SCRAPING_PROWLARR_ENABLED=false
RIVEN_SCRAPING_PROWLARR_URL=
RIVEN_SCRAPING_PROWLARR_API_KEY=

# =========================
# SCRAPING — ORIONOID
# =========================
RIVEN_SCRAPING_ORIONOID_ENABLED=false
RIVEN_SCRAPING_ORIONOID_API_KEY=
RIVEN_SCRAPING_ORIONOID_CACHED_RESULTS_ONLY=false

# =========================
# SCRAPING — ZILEAN
# =========================
RIVEN_SCRAPING_ZILEAN_ENABLED=false
RIVEN_SCRAPING_ZILEAN_URL=

# =========================
# SCRAPING — COMET
# =========================
RIVEN_SCRAPING_COMET_ENABLED=false
RIVEN_SCRAPING_COMET_URL=

# =========================
# SCRAPING — RARBG
# =========================
RIVEN_SCRAPING_RARBG_ENABLED=false
RIVEN_SCRAPING_RARBG_URL=

# =========================
# DOWNLOADERS — REAL-DEBRID
# =========================
RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=

# =========================
# DOWNLOADERS — DEBRID-LINK
# =========================
RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=false
RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=

# =========================
# DOWNLOADERS — ALL-DEBRID
# =========================
RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=
EOF
else
  # Keep existing values but ensure these are set/updated
  set_env TZ "$TZ_SELECTED"
  set_env ORIGIN "$ORIGIN_SELECTED"
  set_env RIVEN_UPDATERS_LIBRARY_PATH "$LIBRARY_PATH"
  set_env RIVEN_UPDATERS_UPDATER_INTERVAL "120"
fi
ok ".env ready"

############################################
# MEDIA SERVER (REQUIRED) — URLs AUTO, ASK KEYS ONLY
############################################
banner "Media Server Selection (REQUIRED)"

MEDIA_PROFILE=""
MEDIA_HEALTH_URL=""

while true; do
  echo "1) Jellyfin"
  echo "2) Plex"
  echo "3) Emby"
  read -rp "Select ONE media server: " MEDIA_SEL

  case "$MEDIA_SEL" in
    1)
      MEDIA_PROFILE="jellyfin"
      MEDIA_HEALTH_URL="http://localhost:8096"

      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED "true"
      set_env RIVEN_UPDATERS_JELLYFIN_URL "http://jellyfin:8096"
      set_env RIVEN_UPDATERS_PLEX_ENABLED "false"
      set_env RIVEN_UPDATERS_EMBY_ENABLED "false"

      set_env RIVEN_UPDATERS_JELLYFIN_API_KEY "$(require_non_empty "Jellyfin API Key")"
      break
      ;;
    2)
      MEDIA_PROFILE="plex"
      MEDIA_HEALTH_URL="http://localhost:32400/web"

      set_env RIVEN_UPDATERS_PLEX_ENABLED "true"
      set_env RIVEN_UPDATERS_PLEX_URL "http://plex:32400"
      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED "false"
      set_env RIVEN_UPDATERS_EMBY_ENABLED "false"

      set_env RIVEN_UPDATERS_PLEX_TOKEN "$(require_non_empty "Plex Token")"
      break
      ;;
    3)
      MEDIA_PROFILE="emby"
      MEDIA_HEALTH_URL="http://localhost:8097"

      set_env RIVEN_UPDATERS_EMBY_ENABLED "true"
      set_env RIVEN_UPDATERS_EMBY_URL "http://emby:8097"
      set_env RIVEN_UPDATERS_PLEX_ENABLED "false"
      set_env RIVEN_UPDATERS_JELLYFIN_ENABLED "false"

      set_env RIVEN_UPDATERS_EMBY_API_KEY "$(require_non_empty "Emby API Key")"
      break
      ;;
    *)
      warn "You MUST select a media server"
      ;;
  esac
done

############################################
# DOWNLOADERS (REQUIRED) — >= 1
############################################
banner "Downloader Selection (REQUIRED)"

# reset to false each run, then enable selections
set_env RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED "false"
set_env RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED "false"
set_env RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED "false"

DL_OK=false
while ! $DL_OK; do
  echo "1) Real-Debrid"
  echo "2) All-Debrid"
  echo "3) Debrid-Link"
  read -rp "Select at least ONE downloader (space-separated): " DL_SEL

  for sel in $DL_SEL; do
    case "$sel" in
      1)
        set_env RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED "true"
        set_env RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY "$(require_non_empty "Real-Debrid API Key")"
        DL_OK=true
        ;;
      2)
        set_env RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED "true"
        set_env RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY "$(require_non_empty "All-Debrid API Key")"
        DL_OK=true
        ;;
      3)
        set_env RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED "true"
        set_env RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY "$(require_non_empty "Debrid-Link API Key")"
        DL_OK=true
        ;;
    esac
  done

  $DL_OK || warn "At least ONE downloader is REQUIRED"
done

############################################
# SCRAPERS (REQUIRED) — >= 1
############################################
banner "Scraper Selection (REQUIRED)"

# reset to false each run, then enable selections
set_env RIVEN_SCRAPING_TORRENTIO_ENABLED "false"
set_env RIVEN_SCRAPING_PROWLARR_ENABLED "false"
set_env RIVEN_SCRAPING_ZILEAN_ENABLED "false"
set_env RIVEN_SCRAPING_COMET_ENABLED "false"
set_env RIVEN_SCRAPING_JACKETT_ENABLED "false"

SC_OK=false
while ! $SC_OK; do
  echo "1) Torrentio"
  echo "2) Prowlarr"
  echo "3) Zilean"
  echo "4) Comet"
  echo "5) Jackett"
  read -rp "Select at least ONE scraper (space-separated): " SC_SEL

  for sel in $SC_SEL; do
    case "$sel" in
      1)
        set_env RIVEN_SCRAPING_TORRENTIO_ENABLED "true"
        # ratelimit stays true by default in env template
        SC_OK=true
        ;;
      2)
        set_env RIVEN_SCRAPING_PROWLARR_ENABLED "true"
        set_env RIVEN_SCRAPING_PROWLARR_URL "$(require_url "Prowlarr URL")"
        set_env RIVEN_SCRAPING_PROWLARR_API_KEY "$(require_non_empty "Prowlarr API Key")"
        SC_OK=true
        ;;
      3)
        set_env RIVEN_SCRAPING_ZILEAN_ENABLED "true"
        set_env RIVEN_SCRAPING_ZILEAN_URL "$(require_url "Zilean URL")"
        SC_OK=true
        ;;
      4)
        set_env RIVEN_SCRAPING_COMET_ENABLED "true"
        set_env RIVEN_SCRAPING_COMET_URL "$(require_url "Comet URL")"
        SC_OK=true
        ;;
      5)
        set_env RIVEN_SCRAPING_JACKETT_ENABLED "true"
        set_env RIVEN_SCRAPING_JACKETT_URL "$(require_url "Jackett URL")"
        set_env RIVEN_SCRAPING_JACKETT_API_KEY "$(require_non_empty "Jackett API Key")"
        SC_OK=true
        ;;
    esac
  done

  $SC_OK || warn "At least ONE scraper is REQUIRED"
done

############################################
# STARTUP ORDER (REQUIRED): MEDIA -> RIVEN
############################################
banner "Starting Media Server First"
docker compose --profile "$MEDIA_PROFILE" up -d
wait_for_url "$MEDIA_PROFILE" "$MEDIA_HEALTH_URL" 300

banner "Starting Riven"
docker compose pull
docker compose up -d riven-db riven riven-frontend

banner "Install Complete"
ok "Riven is configured and running"
ok "Frontend: http://localhost:3000 (ORIGIN=${ORIGIN_SELECTED})"