#!/usr/bin/env bash

ensure_riven_rshared_mount() {
  local mount_path="$MOUNT_PATH"
  local service_name='riven-bind-shared.service'

  banner 'Ensuring rshared mount for Riven'

  mkdir -p "$mount_path"

  if findmnt -no PROPAGATION "$mount_path" 2>/dev/null | grep -q shared; then
    ok 'Mount already rshared'
    return
  fi

  warn 'Mount is not rshared — installing systemd unit'

  cat > "/etc/systemd/system/$service_name" <<EOF_SYSTEMD
[Unit]
Description=Make Riven mount bind shared
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --bind $mount_path $mount_path
ExecStart=/usr/bin/mount --make-rshared $mount_path
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now "$service_name"

  findmnt -no PROPAGATION "$mount_path" | grep -q shared \
    && ok "rshared mount enforced at $mount_path" \
    || fail "Failed to enforce rshared mount on $mount_path"
}
