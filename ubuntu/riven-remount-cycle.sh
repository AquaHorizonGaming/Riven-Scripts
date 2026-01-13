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

UNMOUNT_RETRIES=5
WAIT_BETWEEN=2
REMOUNT_WAIT=5
VERSION=1.0

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


############################################
# MOUNT PATH PROMPT
############################################
section "Mount Configuration"
read -rp "Mount path [${DEFAULT_MOUNT}]: " MOUNT_PATH
MOUNT_PATH="${MOUNT_PATH:-$DEFAULT_MOUNT}"
ok "Using mount path: $MOUNT_PATH"

############################################
# MEDIA SERVER SELECTION
############################################
section "Media Server Selection"
echo "1) Plex"
echo "2) Jellyfin"
echo "3) Emby"
echo "4) Custom container name"
read -rp "Choice [1-4]: " MEDIA_CHOICE

case "$MEDIA_CHOICE" in
  1) MEDIA_CONTAINER="plex" ;;
  2) MEDIA_CONTAINER="jellyfin" ;;
  3) MEDIA_CONTAINER="emby" ;;
  4) read -rp "Container name: " MEDIA_CONTAINER ;;
  *) fail "Invalid selection" ;;
esac

ok "Using media container: $MEDIA_CONTAINER"

############################################
# STOP CONTAINERS
############################################
section "Stopping Containers"
docker stop "$RIVEN_CONTAINER" >/dev/null 2>&1 || true
ok "Riven stopped"

docker stop "$MEDIA_CONTAINER" >/dev/null 2>&1 || true
ok "Media server stopped"

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
  umount "$MOUNT_PATH" || true
  sleep "$WAIT_BETWEEN"

  if ! is_mounted; then
    ok "Mount successfully unmounted"
    break
  fi
done

if is_mounted; then
  fail "Mount still present after retries"
fi

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
# START CONTAINERS
############################################
section "Starting Containers"

docker start "$RIVEN_CONTAINER" >/dev/null
ok "Riven started"

docker start "$MEDIA_CONTAINER" >/dev/null
ok "Media server started"

sleep 5
docker restart "$MEDIA_CONTAINER" >/dev/null
ok "Media server restarted (post-mount)"

############################################
# DONE
############################################
section "Complete"
ok "Riven bind-remount cycle finished successfully"
