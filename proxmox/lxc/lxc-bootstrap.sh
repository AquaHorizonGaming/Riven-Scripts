#!/usr/bin/env bash
set -euo pipefail

echo "== LXC Bootstrap: install Docker + Compose =="

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release fuse3 uidmap jq

# Install Docker from Docker's official repo
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

echo "Docker version:"
docker --version
echo "Docker Compose version:"
docker compose version
