#!/usr/bin/env bash

prepare_filesystem() {
  banner 'Filesystem'

  mkdir -p "$BACKEND_PATH" "$MOUNT_PATH" "$INSTALL_DIR"

  chown "$TARGET_UID:$TARGET_GID" "$BACKEND_PATH" "$MOUNT_PATH" \
    || fail 'Failed to chown backend or mount path'
  chown "$TARGET_UID:$TARGET_GID" "$INSTALL_DIR" \
    || fail 'Failed to chown install dir'

  ok "Filesystem ready (owner: $TARGET_UID:$TARGET_GID)"
}
