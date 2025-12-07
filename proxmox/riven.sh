#!/usr/bin/env bash

# Proxmox helper script to create a Riven LXC (Debian 12, unprivileged)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_FUNC_LOCAL="${SCRIPT_DIR}/build.func"
if [ -f "$BUILD_FUNC_LOCAL" ]; then
  source "$BUILD_FUNC_LOCAL"
else
  # Fallback to remote build.func when running directly via curl from GitHub
  source <(curl -s https://raw.githubusercontent.com/rivenmedia/distributables/main/proxmox/build.func)
fi

function header_info {
clear
cat <<'EOF'
.______       __  ____    ____  _______ .__   __. 
|   _  \     |  | \   \  /   / |   ____||  \ |  | 
|  |_)  |    |  |  \   \/   /  |  |__   |   \|  | 
|      /     |  |   \      /   |   __|  |  . `  | 
|  |\  \----.|  |    \    /    |  |____ |  |\   | 
| _| `._____||__|     \__/     |_______||__| \__| 

Riven LXC Helper
EOF
}

header_info
echo -e "Loading..."

APP="Riven"
var_disk="40"
var_cpu="4"
var_ram="8192"
var_os="debian"
var_version="12"

variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  RIVEN_FRONTEND_ORIGIN=""
  echo_default
}

function update_script() {
  msg_error "No ${APP} update script is available yet."
  exit 1
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} backend should be reachable at:  ${BL}http://<CT-IP>:8080/scalar${CL}"
echo -e "${APP} frontend should be reachable at: ${BL}http://<CT-IP>:3000${CL}\n\n"
echo -e "To edit the backend settings directly, they are accessible at ${BL}/riven/src/data/settings.json${CL}\n"

echo -e "To share a host media directory with this Riven container, run on the Proxmox host:"
echo -e "  ${BL}pct set <RIVEN_CT_ID> -mp0 /path/to/media,mp=/mnt/riven${CL}"
echo -e "Then add the same host path into your media server container (Plex/Jellyfin/Emby/etc):"
echo -e "  ${BL}pct set <MEDIA_CT_ID> -mp1 /path/to/media,mp=/mnt/riven${CL}\n"
echo -e "Ensure the host media directory is world-readable (e.g. ${BL}chmod 755 /path/to/media${CL}) so the riven user can read files even if they are owned by another user like plex.\n"
