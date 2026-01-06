#!/usr/bin/env bash
set -euo pipefail

# Creates an unprivileged Debian 12 LXC configured for Docker + FUSE (and optional GPU)

usage() {
  cat <<EOF
Usage: lxc-create.sh --ctid ID --hostname NAME --storage STORAGE --disk-gb N --mem-mb N --cores N --net0 NET0 [--host-riven-path PATH] [--gpu yes|no]
EOF
}

CTID=""; HOSTNAME="riven"; STORAGE="local"; DISK_GB="16"; MEM_MB="4096"; CORES="4"; NET0="name=eth0,bridge=vmbr0,ip=dhcp"
HOST_RIVEN_PATH=""
GPU="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctid) CTID="$2"; shift 2;;
    --hostname) HOSTNAME="$2"; shift 2;;
    --storage) STORAGE="$2"; shift 2;;
    --disk-gb) DISK_GB="$2"; shift 2;;
    --mem-mb) MEM_MB="$2"; shift 2;;
    --cores) CORES="$2"; shift 2;;
    --net0) NET0="$2"; shift 2;;
    --host-riven-path) HOST_RIVEN_PATH="$2"; shift 2;;
    --gpu) GPU="$2"; shift 2;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$CTID" ]]; then usage; exit 1; fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: Missing $1"; exit 1; }; }
require_cmd pveam
require_cmd pvesm
require_cmd pct

# Find Debian 12 template (download if missing)
TPL_NAME="$(pveam available --section system | awk '/debian-12-standard/ {print $2}' | tail -n1)"
if [[ -z "$TPL_NAME" ]]; then
  echo "ERROR: Could not find Debian 12 template in pveam catalog."
  exit 1
fi

if ! pveam list "$STORAGE" | awk '{print $1}' | grep -qx "$TPL_NAME"; then
  echo "Downloading Debian 12 template to storage '$STORAGE'..."
  pveam download "$STORAGE" "$TPL_NAME"
fi

# Root password (random) for convenience
ROOT_PASS="$(openssl rand -base64 18 | tr -d '\n' | tr -d '=+/')"
echo "CT root password (SAVE THIS): $ROOT_PASS"

# Create container
echo "Creating CT $CTID..."
pct create "$CTID" "$STORAGE:vztmpl/$TPL_NAME" \
  --hostname "$HOSTNAME" \
  --unprivileged 1 \
  --features "nesting=1,keyctl=1,fuse=1" \
  --cores "$CORES" \
  --memory "$MEM_MB" \
  --swap 1024 \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "$NET0" \
  --password "$ROOT_PASS" \
  --onboot 1 \
  --start 1

CONF="/etc/pve/lxc/${CTID}.conf"

# Docker-in-LXC hardening/compat
# (These are common requirements for Docker in an unprivileged LXC on Proxmox.)
{
  echo ""
  echo "# --- Riven/Docker requirements ---"
  echo "lxc.apparmor.profile: unconfined"
  echo "lxc.cgroup2.devices.allow: a"
  echo "lxc.mount.auto: proc:rw sys:rw"
} >> "$CONF"

# Pass /dev/fuse
{
  echo "# Pass FUSE"
  echo "lxc.cgroup2.devices.allow: c 10:229 rwm"
  echo "lxc.mount.entry: /dev/fuse dev/fuse none bind,create=file,optional 0 0"
} >> "$CONF"

# Pass GPU (optional)
if [[ "${GPU}" == "yes" ]]; then
  {
    echo "# Pass GPU (DRI)"
    echo "lxc.cgroup2.devices.allow: c 226:* rwm"
    echo "lxc.mount.entry: /dev/dri dev/dri none bind,create=dir,optional 0 0"
  } >> "$CONF"
fi

# Bind-mount host path into CT as /srv/riven (recommended)
if [[ -n "$HOST_RIVEN_PATH" ]]; then
  if [[ ! -d "$HOST_RIVEN_PATH" ]]; then
    echo "Creating host path: $HOST_RIVEN_PATH"
    mkdir -p "$HOST_RIVEN_PATH"
  fi
  echo "# Bind host storage into CT"
  echo "mp0: ${HOST_RIVEN_PATH},mp=/srv/riven" >> "$CONF"
fi

echo "Restarting CT to apply config changes..."
pct stop "$CTID"
pct start "$CTID"

echo "CT $CTID created and configured."
