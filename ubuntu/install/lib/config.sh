#!/usr/bin/env bash

INSTALL_DIR="/opt/riven"
BACKEND_PATH="/mnt/riven/backend"
MOUNT_PATH="/mnt/riven/mount"
LOG_DIR="/tmp/logs/riven"

MEDIA_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.media.yml"
RIVEN_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"

DEFAULT_ORIGIN="http://localhost:3000"
INSTALL_VERSION="v0.6"

print_installer_version() {
  : "${INSTALL_VERSION:=unknown}"
  ok "Installer version: ${INSTALL_VERSION}"
}
