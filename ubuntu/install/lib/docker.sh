#!/usr/bin/env bash

install_system_dependencies() {
  banner 'System Dependencies'

  if dpkg -s ca-certificates curl gnupg lsb-release openssl fuse3 >/dev/null 2>&1; then
    ok 'System dependencies already installed'
    return
  fi

  apt-get update || fail 'apt update failed'
  apt-get install -y ca-certificates curl gnupg lsb-release openssl fuse3 \
    || fail 'dependency install failed'
  ok 'System dependencies installed'
}

ensure_docker_installed() {
  banner 'Docker'

  if command -v docker >/dev/null 2>&1; then
    ok 'Docker already installed'
    return
  fi

  echo '[*] Installing Docker — this may take several minutes depending on your connection...'
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  ok 'Docker installed'
}

setup_docker_group() {
  banner 'DockerGroup'

  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker || fail 'Failed to create docker group'
    ok 'Docker group created'
  else
    ok 'Docker group already exists'
  fi

  if [[ -z "${TARGET_USER:-}" ]]; then
    warn 'No non-root user found to add to docker group'
    return
  fi

  if id -nG "$TARGET_USER" | grep -qw docker; then
    ok "User '$TARGET_USER' already in docker group"
    return
  fi

  usermod -aG docker "$TARGET_USER" || fail "Failed to add $TARGET_USER to docker group"
  ok "User '$TARGET_USER' added to docker group"
  warn 'Log out and back in for Docker permissions to apply'
}
