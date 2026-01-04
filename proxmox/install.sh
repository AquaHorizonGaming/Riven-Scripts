#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Riven Proxmox LXC Installer (Docker-based)
# Run on Proxmox host as root
#
# One-liner supported:
# bash -c "$(wget -qLO - https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/proxmox/install.sh)"
###############################################################################

[[ "$EUID" -ne 0 ]] && { echo "ERROR: Run as root on Proxmox host"; exit 1; }

###############################################################################
# Helpers
###############################################################################
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: $1"
    exit 1
  }
}

###############################################################################
# Requirements
###############################################################################
require_cmd pveversion
require_cmd pct
require_cmd pvesm
require_cmd curl

###############################################################################
# Proxmox version check (8.1+)
###############################################################################
PVE_VER_RAW="$(pveversion | head -n1)"
PVE_VER="$(echo "$PVE_VER_RAW" | sed -nE 's/.*pve-manager\/([0-9]+)\.([0-9]+).*/\1.\2/p')"

if [[ -z "$PVE_VER" ]]; then
  echo "WARNING: Could not parse Proxmox version from: $PVE_VER_RAW"
else
  MAJ="${PVE_VER%.*}"
  MIN="${PVE_VER#*.}"
  if (( MAJ < 8 )) || (( MAJ == 8 && MIN < 1 )); then
    echo "ERROR: Proxmox 8.1+ required. Detected: $PVE_VER_RAW"
    exit 1
  fi
fi

echo "== Riven Proxmox LXC (Docker) Installer =="

###############################################################################
# Download LXC installer components from GitHub
###############################################################################
BASE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/proxmox/lxc"
WORKDIR="/tmp/riven-proxmox-lxc"

echo "📥 Downloading installer components from GitHub..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

fetch() {
  local file="$1"
  echo "  - $file"
  curl -fsSL "$BASE_URL/$file" -o "$file"
}

fetch lxc-create.sh
fetch lxc-bootstrap.sh
fetch riven-install.sh
fetch docker-compose.yml
fetch upgrade.sh

chmod +x lxc-create.sh lxc-bootstrap.sh riven-install.sh upgrade.sh

###############################################################################
# Defaults
###############################################################################
DEFAULT_CTID=""
while :; do
  CANDIDATE=$(( (RANDOM % 900) + 100 ))
  if ! pct status "$CANDIDATE" >/dev/null 2>&1; then
    DEFAULT_CTID="$CANDIDATE"
    break
  fi
done

read -rp "Container ID (CTID) [${DEFAULT_CTID}]: " CTID
CTID="${CTID:-$DEFAULT_CTID}"

if pct status "$CTID" >/dev/null 2>&1; then
  echo "ERROR: CTID $CTID already exists."
  exit 1
fi

read -rp "Hostname [riven]: " HOSTNAME
HOSTNAME="${HOSTNAME:-riven}"

read -rp "Rootfs disk size (GB) [16]: " DISK_GB
DISK_GB="${DISK_GB:-16}"

read -rp "Memory (MB) [4096]: " MEM_MB
MEM_MB="${MEM_MB:-4096}"

read -rp "CPU cores [4]: " CORES
CORES="${CORES:-4}"

DEFAULT_STORAGE="$(pvesm status | awk 'NR>1{print $1}' | head -n1)"
DEFAULT_STORAGE="${DEFAULT_STORAGE:-local}"
read -rp "Storage for rootfs/template [${DEFAULT_STORAGE}]: " STORAGE
STORAGE="${STORAGE:-$DEFAULT_STORAGE}"

read -rp "Bridge [vmbr0]: " BRIDGE
BRIDGE="${BRIDGE:-vmbr0}"

read -rp "Network config (dhcp or static like 192.168.1.50/24,gw=192.168.1.1) [dhcp]: " NETCFG
NETCFG="${NETCFG:-dhcp}"

if [[ "$NETCFG" == "dhcp" ]]; then
  NET0="name=eth0,bridge=${BRIDGE},ip=dhcp"
else
  NET0="name=eth0,bridge=${BRIDGE},ip=${NETCFG}"
fi

###############################################################################
# Optional host mount
###############################################################################
echo
echo "Optional: bind-mount a host path into the LXC as /mnt/riven"
read -rp "Host path to mount (leave blank to skip): " HOST_RIVEN_PATH

###############################################################################
# GPU passthrough
###############################################################################
GPU_ENABLE="no"
if [[ -d /dev/dri ]]; then
  read -rp "Detected /dev/dri. Enable GPU passthrough? [Y/n]: " GPU_ANS
  GPU_ANS="${GPU_ANS:-Y}"
  [[ "$GPU_ANS" =~ ^[Yy]$ ]] && GPU_ENABLE="yes"
else
  read -rp "No /dev/dri detected. Force GPU passthrough anyway? [y/N]: " GPU_ANS
  GPU_ANS="${GPU_ANS:-N}"
  [[ "$GPU_ANS" =~ ^[Yy]$ ]] && GPU_ENABLE="yes"
fi

###############################################################################
# Create LXC
###############################################################################
bash "$WORKDIR/lxc-create.sh" \
  --ctid "$CTID" \
  --hostname "$HOSTNAME" \
  --storage "$STORAGE" \
  --disk-gb "$DISK_GB" \
  --mem-mb "$MEM_MB" \
  --cores "$CORES" \
  --net0 "$NET0" \
  --host-riven-path "$HOST_RIVEN_PATH" \
  --gpu "$GPU_ENABLE"

###############################################################################
# Push files into CT
###############################################################################
echo "📦 Pushing installer files into CT $CTID..."
pct push "$CTID" "$WORKDIR/lxc-bootstrap.sh"   /root/lxc-bootstrap.sh   -perms 0755
pct push "$CTID" "$WORKDIR/riven-install.sh"  /root/riven-install.sh  -perms 0755
pct push "$CTID" "$WORKDIR/docker-compose.yml" /root/docker-compose.yml -perms 0644
pct push "$CTID" "$WORKDIR/upgrade.sh"         /root/upgrade.sh        -perms 0755

###############################################################################
# Bootstrap Docker
###############################################################################
echo "🐳 Installing Docker inside CT..."
pct exec "$CTID" -- bash /root/lxc-bootstrap.sh

###############################################################################
# Install Riven
###############################################################################
echo "🚀 Deploying Riven stack..."
pct exec "$CTID" -- bash /root/riven-install.sh

###############################################################################
# Final info
###############################################################################
echo
echo "✅ Installation complete."
echo "Find CT IP:"
echo "  pct exec $CTID -- hostname -I"
echo
echo "Backend  : http://<CT-IP>:8080"
echo "Frontend : http://<CT-IP>:3000"
echo
echo "Logs:"
echo "  pct exec $CTID -- docker logs -f riven"
echo "  pct exec $CTID -- docker logs -f riven-db"
