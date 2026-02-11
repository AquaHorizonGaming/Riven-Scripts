#!/usr/bin/env bash

ensure_docker_installed() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed"
  else
    echo "[*] Installing Docker — this may take several minutes depending on your connection..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    ok "Docker installed"
  fi
}

setup_docker_group() {
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker || fail "Failed to create docker group"
    ok "Docker group created"
  else
    ok "Docker group already exists"
  fi

  local user=""
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    user="$SUDO_USER"
  else
    user="$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)"
  fi

  if [[ -z "$user" ]]; then
    warn "No non-root user found to add to docker group"
    return
  fi

  if id -nG "$user" | grep -qw docker; then
    ok "User '$user' already in docker group"
  else
    usermod -aG docker "$user" || fail "Failed to add $user to docker group"
    ok "User '$user' added to docker group"
    warn "Log out and back in for Docker permissions to apply"
  fi
}
