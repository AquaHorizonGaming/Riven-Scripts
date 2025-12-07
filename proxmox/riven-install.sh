#!/usr/bin/env bash

# Baremetal Riven installer for Debian LXC (unprivileged)
# - Installs system dependencies (Python, Node, Postgres, FUSE, build tools, ffmpeg, etc.)
# - Configures FUSE and Python capabilities for RivenVFS
# - Sets up local PostgreSQL
# - Installs Riven backend (Python/uv) and frontend (Node/pnpm)
# - Creates env config in /etc/riven and systemd services for both components

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

export DEBIAN_FRONTEND=noninteractive

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
	curl sudo mc git ffmpeg vim \
	python3 python3-venv python3-dev build-essential libffi-dev libpq-dev libfuse3-dev pkg-config \
	fuse3 libcap2-bin ca-certificates openssl \
	postgresql postgresql-contrib postgresql-client
msg_ok "Installed Dependencies"

msg_info "Configuring FUSE"
echo 'user_allow_other' > /etc/fuse.conf
msg_ok "Configured FUSE"

msg_info "Configuring Python capabilities for FUSE"
PY_BIN=$(command -v python3 || true)
if [ -n "$PY_BIN" ]; then
	setcap cap_sys_admin+ep "$PY_BIN" 2>/dev/null || true
fi
msg_ok "Configured Python capabilities"

msg_info "Installing Node.js (24.x) and pnpm"
curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null 2>&1 || {
	msg_error "Failed to configure NodeSource repository for Node.js"
	exit 1
}
$STD apt-get install -y nodejs
npm install -g pnpm >/dev/null 2>&1 || {
	msg_error "Failed to install pnpm globally"
	exit 1
}
msg_ok "Installed Node.js and pnpm"

msg_info "Configuring PostgreSQL"
$STD systemctl enable postgresql
$STD systemctl start postgresql
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='riven'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE DATABASE riven;" >/dev/null 2>&1 || true
fi
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';" >/dev/null 2>&1 || true
msg_ok "Configured PostgreSQL"

msg_info "Creating Riven user and directories"
if ! id -u riven >/dev/null 2>&1; then
  useradd -r -d /riven -s /usr/sbin/nologin riven || true
fi
  mkdir -p /riven /riven/data /mount /opt/riven-frontend /etc/riven
  chown -R riven:riven /riven /riven/data /mount /opt/riven-frontend
  chmod 755 /riven /riven/data /mount || true
  # Cache directory for RivenVFS (not shared across LXCs)
  mkdir -p /dev/shm/riven-cache
  chown riven:riven /dev/shm/riven-cache || true
  chmod 700 /dev/shm/riven-cache || true
msg_ok "Created Riven user and directories"

msg_info "Installing uv package manager"
curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || true
export PATH="${HOME}/.local/bin:$PATH"
UV_BIN="${HOME}/.local/bin/uv"
if [ ! -x "$UV_BIN" ]; then
  msg_error "uv was not installed correctly"
  exit 1
fi
install -m 755 "$UV_BIN" /usr/local/bin/uv >/dev/null 2>&1 || true
UV_BIN="/usr/local/bin/uv"
msg_ok "Installed uv"

msg_info "Installing Riven backend"
if [ ! -d /riven/src ]; then
	git clone https://github.com/rivenmedia/riven.git /riven/src >/dev/null 2>&1 || {
		msg_error "Failed to clone Riven backend repository"
		exit 1
	}
else
	cd /riven/src
	git pull --rebase >/dev/null 2>&1 || true
fi
chown -R riven:riven /riven/src || true
cd /riven/src
# Ensure project virtual environment exists
if [ ! -d .venv ]; then
	sudo -u riven -H "$UV_BIN" venv >/dev/null 2>&1 || {
		msg_error "Failed to create Python virtual environment with uv"
		exit 1
	}
fi

VENV_PY_BIN="/riven/src/.venv/bin/python3"
if [ -x "$VENV_PY_BIN" ]; then
	setcap cap_sys_admin+ep "$VENV_PY_BIN" 2>/dev/null || true
fi

sudo -u riven -H "$UV_BIN" sync --no-dev --frozen >/dev/null 2>&1 || \
	sudo -u riven -H "$UV_BIN" sync --no-dev >/dev/null 2>&1 || {
	msg_error "Failed to install Riven backend dependencies with uv"
	exit 1
}
chown -R riven:riven /riven
msg_ok "Installed Riven backend"

msg_info "Configuring Riven backend environment"

BACKEND_ENV="/etc/riven/backend.env"
FRONTEND_ENV="/etc/riven/frontend.env"
mkdir -p /etc/riven

# Reuse existing API key if present to keep backend and frontend in sync
if [ -f "$BACKEND_ENV" ]; then
  RIVEN_API_KEY=$(grep '^RIVEN_API_KEY=' "$BACKEND_ENV" | head -n1 | cut -d= -f2- || true)
fi
if [ -z "${RIVEN_API_KEY:-}" ]; then
  RIVEN_API_KEY=$(openssl rand -hex 16)
fi

if [ ! -f "$BACKEND_ENV" ]; then
  cat <<EOF >"$BACKEND_ENV"
RIVEN_API_KEY=$RIVEN_API_KEY
RIVEN_DATABASE_HOST=postgresql+psycopg2://postgres:postgres@127.0.0.1/riven
RIVEN_FILESYSTEM_MOUNT_PATH=/mount
RIVEN_UPDATERS_LIBRARY_PATH=/mnt/riven
RIVEN_FILESYSTEM_CACHE_DIR=/dev/shm/riven-cache
EOF
  chown riven:riven "$BACKEND_ENV"
  chmod 600 "$BACKEND_ENV"
fi
msg_ok "Configured Riven backend environment"

msg_info "Creating systemd service for Riven backend"
cat <<'EOF' >/etc/systemd/system/riven-backend.service
[Unit]
Description=Riven Backend
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=riven
Group=riven
WorkingDirectory=/riven/src
EnvironmentFile=/etc/riven/backend.env
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
ExecStart=/usr/local/bin/uv run python src/main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
$STD systemctl enable riven-backend.service
$STD systemctl restart riven-backend.service
msg_ok "Created systemd service for Riven backend"

msg_info "Installing Riven frontend"
if [ ! -d /opt/riven-frontend/.git ]; then
  rm -rf /opt/riven-frontend
  git clone https://github.com/rivenmedia/riven-frontend.git /opt/riven-frontend >/dev/null 2>&1 || {
    msg_error "Failed to clone Riven frontend repository"
    exit 1
  }
else
  cd /opt/riven-frontend
  git pull --rebase >/dev/null 2>&1 || true
fi
cd /opt/riven-frontend
	if command -v pnpm >/dev/null 2>&1; then
	  if ! pnpm install >/dev/null 2>&1; then
	    msg_error "pnpm install failed while installing Riven frontend"
	    exit 1
	  fi
	  if ! pnpm run build >/dev/null 2>&1; then
	    msg_error "pnpm run build failed while building Riven frontend"
	    exit 1
	  fi
	  pnpm prune --prod >/dev/null 2>&1 || true
	else
	  msg_error "pnpm is not available; cannot build Riven frontend"
	  exit 1
	fi
chown -R riven:riven /opt/riven-frontend
msg_ok "Installed Riven frontend"

msg_info "Configuring Riven frontend environment"
AUTH_SECRET=$(openssl rand -base64 32)

	# If the host script provided a specific origin (e.g. a reverse proxy URL), use it.
	# Otherwise, fall back to auto-detecting the CT's primary IPv4 and using :3000.
	if [ -n "${RIVEN_FRONTEND_ORIGIN:-}" ]; then
	  FRONTEND_ORIGIN_DEFAULT="$RIVEN_FRONTEND_ORIGIN"
	else
	  CT_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR==1{print $4}' | cut -d/ -f1)
	  if [ -z "$CT_IP" ]; then
	    CT_IP="127.0.0.1"
	  fi
	  FRONTEND_ORIGIN_DEFAULT="http://$CT_IP:3000"
	fi

	if [ ! -f "$FRONTEND_ENV" ]; then
	  cat <<EOF >"$FRONTEND_ENV"
	DATABASE_URL=/riven/data/riven.db
	BACKEND_URL=http://127.0.0.1:8080
	BACKEND_API_KEY=$RIVEN_API_KEY
	AUTH_SECRET=$AUTH_SECRET
	ORIGIN=$FRONTEND_ORIGIN_DEFAULT
	EOF
	  chown root:root "$FRONTEND_ENV"
	  chmod 600 "$FRONTEND_ENV"
	fi
msg_ok "Configured Riven frontend environment"

msg_info "Creating systemd service for Riven frontend"
cat <<'EOF' >/etc/systemd/system/riven-frontend.service
[Unit]
Description=Riven Frontend
After=network-online.target riven-backend.service
Wants=network-online.target

[Service]
Type=simple
User=riven
Group=riven
WorkingDirectory=/opt/riven-frontend
EnvironmentFile=/etc/riven/frontend.env
ExecStart=/usr/bin/node /opt/riven-frontend/build
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
$STD systemctl enable riven-frontend.service
$STD systemctl restart riven-frontend.service
msg_ok "Created systemd service for Riven frontend"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
