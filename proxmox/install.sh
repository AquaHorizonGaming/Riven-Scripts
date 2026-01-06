#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Riven Proxmox LXC Installer (Docker-based)
# Run on Proxmox host as root
#
# One-liner supported:
# bash -c "$(wget -qLO - https://raw.githubusercontent.com/AquaHorizonGaming/Riven-Scripts/main/proxmox/install.sh)"
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

apt_install_if_missing() {
  local bin="$1"
  local pkg="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "📦 Installing: ${pkg} (required for UI prompts)"
    apt-get update -y
    apt-get install -y "$pkg"
  fi
}

# Prefer bridges on Proxmox, fallback to usable interfaces
list_bridges() {
  # Linux bridge devices (e.g., vmbr0)
  ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*$//' || true
}

list_interfaces() {
  ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*$//' \
    | grep -Ev '^(lo|docker|veth|virbr|br-|tun|tap)'
}

whiptail_menu_select() {
  local title="$1"
  local prompt="$2"

  local OPTIONS=()
  while read -r item; do
    [[ -z "$item" ]] && continue
    OPTIONS+=("$item" "")
  done

  if [[ ${#OPTIONS[@]} -eq 0 ]]; then
    return 1
  fi

  whiptail --title "$title" \
    --menu "$prompt" \
    20 70 10 \
    "${OPTIONS[@]}" \
    3>&1 1>&2 2>&3
}

select_network_target_ui() {
  # Ensure whiptail exists
  apt_install_if_missing whiptail whiptail

  local bridges ifaces
  bridges="$(list_bridges)"

  if [[ -n "$bridges" ]]; then
    BRIDGE="$(printf '%s\n' "$bridges" | whiptail_menu_select "Network Bridge" "Select the Proxmox bridge to attach the LXC to:")"
    if [[ -z "$BRIDGE" ]]; then
      echo "❌ No bridge selected. Exiting."
      exit 1
    fi
    echo "✔ Selected bridge: $BRIDGE"
    return 0
  fi

  # Fallback: raw interfaces (not ideal for Proxmox). We still let them pick
  # so we can print a helpful error instead of asking them to type names.
  ifaces="$(list_interfaces || true)"
  if [[ -z "$ifaces" ]]; then
    echo "❌ No usable network interfaces detected."
    exit 1
  fi

  IFACE="$(printf '%s\n' "$ifaces" | whiptail_menu_select "Network Interface" "No bridges detected. Select a network interface:")"
  if [[ -z "$IFACE" ]]; then
    echo "❌ No interface selected. Exiting."
    exit 1
  fi

  echo "⚠ Selected interface (no bridge found): $IFACE"
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

###############################################################################
# Network selection (UI)
###############################################################################
BRIDGE=""
IFACE=""
select_network_target_ui

###############################################################################
# IP config
###############################################################################
read -rp "Network config (dhcp or static like 192.168.1.50/24,gw=192.168.1.1) [dhcp]: " NETCFG
NETCFG="${NETCFG:-dhcp}"

# Default LXC NIC name remains eth0 inside the CT.
if [[ -n "$BRIDGE" ]]; then
  if [[ "$NETCFG" == "dhcp" ]]; then
    NET0="name=eth0,bridge=${BRIDGE},ip=dhcp"
  else
    NET0="name=eth0,bridge=${BRIDGE},ip=${NETCFG}"
  fi
else
  echo "ERROR: No Proxmox bridges detected. Create a vmbr bridge first (e.g., vmbr0) and rerun."
  exit 1
fi

###############################################################################
# Host mount (single unified root)
###############################################################################
echo
echo "Host storage bind-mount into the LXC (recommended)"
echo "This will be mounted inside the CT at: /srv/riven"
echo "Suggested host path: /srv/riven"
read -rp "Host path to mount [ /srv/riven ] (blank to skip): " HOST_RIVEN_PATH
HOST_RIVEN_PATH="${HOST_RIVEN_PATH:-/srv/riven}"

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
pct push "$CTID" "$WORKDIR/lxc-bootstrap.sh"   /root/lxc-bootstrap.sh    -perms 0755
pct push "$CTID" "$WORKDIR/riven-install.sh"   /root/riven-install.sh    -perms 0755
pct push "$CTID" "$WORKDIR/docker-compose.yml" /root/docker-compose.yml  -perms 0644
pct push "$CTID" "$WORKDIR/upgrade.sh"         /root/upgrade.sh          -perms 0755

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
echo "Volumes inside CT (unified):"
echo "  /srv/riven/app      (docker-compose + .env)"
echo "  /srv/riven/backend   (Riven backend persistence)"
echo "  /srv/riven/mount     (FUSE/VFS mount)"
echo "  /srv/riven/media/*   (media server configs)"
echo
echo "Logs:"
echo "  pct exec $CTID -- docker logs -f riven"
echo "  pct exec $CTID -- docker logs -f riven-db"
