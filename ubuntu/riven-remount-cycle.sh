#!/usr/bin/env bash
set -euo pipefail

############################################
# REQUIRE ROOT
############################################
if [[ "$EUID" -ne 0 ]]; then
  echo "❌  Must be run as root"
  exit 1
fi

############################################
# DEFAULTS
############################################
RIVEN_CONTAINER="riven"
DEFAULT_MOUNT="/mnt/riven/mount"

UNMOUNT_RETRIES=3
WAIT_BETWEEN=2
REMOUNT_WAIT=5
WAIT_TIME=5
VERSION=2.0

############################################
# OUTPUT HELPERS
############################################
section() { echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "▶ $1"; }
ok()      { echo "✔ $1"; }
warn()    { echo "⚠ $1"; }
fail()    { echo "✖ $1"; exit 1; }

is_mounted() {
  findmnt -T "$MOUNT_PATH" >/dev/null 2>&1
}

############################################
# VERSION MODULE
############################################
show_version() {
  section "Riven Bind-Remount Cycle"
  ok "Version: v$VERSION"
}

show_version

############################################
# MOUNT PATH PROMPT
############################################
section "Mount Configuration"
read -rp "Mount path [${DEFAULT_MOUNT}]: " MOUNT_PATH
MOUNT_PATH="${MOUNT_PATH:-$DEFAULT_MOUNT}"
ok "Using mount path: $MOUNT_PATH"

############################################
# MEDIA RUNTIME SELECTION
############################################
section "Media Server Runtime"
echo "1) Docker"
echo "2) Systemd service"
read -rp "Choice [1-2]: " MEDIA_RUNTIME

case "$MEDIA_RUNTIME" in
  1)
    MEDIA_MODE="docker"
    ok "Media server will be controlled via Docker"
    ;;
  2)
    MEDIA_MODE="systemd"
    ok "Media server will be controlled via systemd"
    ;;
  *)
    fail "Invalid runtime selection"
    ;;
esac

############################################
# MEDIA SERVER SELECTION
############################################
section "Media Server Selection"
echo "1) Plex"
echo "2) Jellyfin"
echo "3) Emby"
echo "4) Custom name"
read -rp "Choice [1-4]: " MEDIA_CHOICE

case "$MEDIA_CHOICE" in
  1) MEDIA_NAME="plex" ;;
  2) MEDIA_NAME="jellyfin" ;;
  3) MEDIA_NAME="emby" ;;
  4) read -rp "Enter media name: " MEDIA_NAME ;;
  *) fail "Invalid selection" ;;
esac

ok "Selected media server: $MEDIA_NAME"

############################################
# MEDIA TARGET RESOLUTION
############################################
if [[ "$MEDIA_MODE" == "docker" ]]; then
  MEDIA_CONTAINER="$MEDIA_NAME"
  ok "Using Docker container: $MEDIA_CONTAINER"
else
  case "$MEDIA_NAME" in
    plex)     MEDIA_SERVICE="plexmediaserver" ;;
    jellyfin) MEDIA_SERVICE="jellyfin" ;;
    emby)     MEDIA_SERVICE="emby-server" ;;
    *)
      read -rp "Enter systemd service name: " MEDIA_SERVICE
      ;;
  esac
  ok "Using systemd service: $MEDIA_SERVICE"
fi

############################################
# STOP SERVICES
############################################
section "Stopping Services"

docker stop "$RIVEN_CONTAINER" >/dev/null 2>&1 || true
ok "Riven container stopped"

if [[ "$MEDIA_MODE" == "docker" ]]; then
  docker stop "$MEDIA_CONTAINER" >/dev/null 2>&1 || true
  ok "Media container stopped"
else
  systemctl stop "$MEDIA_SERVICE"
  ok "Media service stopped"
fi

############################################
# UNMOUNT
############################################
section "Unmounting Mount Path"

for attempt in $(seq 1 $UNMOUNT_RETRIES); do
  if ! is_mounted; then
    ok "Mount is already unmounted"
    break
  fi

  warn "Unmount attempt $attempt"

  if umount "$MOUNT_PATH" 2>&1 | grep -q "not mounted"; then
    ok "Mount was already unmounted"
    break
  fi

  sleep "$WAIT_BETWEEN"

  if ! is_mounted; then
    ok "Mount successfully unmounted"
    break
  fi
done

############################################
# REMOUNT (BIND + RSHARED)
############################################
section "Re-establishing Mount"

mount --bind "$MOUNT_PATH" "$MOUNT_PATH"
ok "Bind mount created"

mount --make-rshared "$MOUNT_PATH"
ok "Mount marked as rshared"

############################################
# VERIFY PROPAGATION
############################################
section "Verifying Propagation"

findmnt -T "$MOUNT_PATH" -o TARGET,PROPAGATION

PROP=$(findmnt -T "$MOUNT_PATH" -o PROPAGATION -n)
if [[ "$PROP" != "shared" && "$PROP" != "rshared" ]]; then
  fail "Propagation incorrect: $PROP"
fi

ok "Propagation verified: $PROP"

############################################
# START SERVICES
############################################
section "Starting Services"

# 1. Start media server
if [[ "$MEDIA_MODE" == "docker" ]]; then
  docker start "$MEDIA_CONTAINER" >/dev/null
  ok "Media container started"
else
  systemctl start "$MEDIA_SERVICE"
  ok "Media service started"
fi

# 2. Wait before starting Riven
sleep 5

# 3. Start Riven
docker start "$RIVEN_CONTAINER" >/dev/null
ok "Riven container started"

# 4. Wait for mount propagation
sleep 15

# 5. Restart media server (post-mount)
if [[ "$MEDIA_MODE" == "docker" ]]; then
  docker restart "$MEDIA_CONTAINER" >/dev/null
  ok "Media container restarted (post-mount)"
else
  systemctl restart "$MEDIA_SERVICE"
  ok "Media service restarted (post-mount)"
fi


############################################
# DONE
############################################
section "Complete"
ok "Riven bind-remount cycle finished successfully"
