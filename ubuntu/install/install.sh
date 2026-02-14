#!/usr/bin/env bash
set -euo pipefail

default_owner="AquaHorizonGaming"
default_repo="riven-scripts"
default_branch="fix-install-script"
default_path="ubuntu/install"
BASE_URL="$(printf '%s' "https://raw.githubusercontent.com/${default_owner}/${default_repo}/${default_branch}/${default_path}")"

TMP_ROOT="/tmp/riven-install"
mkdir -p "$TMP_ROOT"
TMP_DIR="$(mktemp -d "$TMP_ROOT/run.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/lib"

modules=(
  "helpers.sh"
  "logging.sh"
  "root.sh"
  "args.sh"
  "users.sh"
  "docker.sh"
  "filesystem.sh"
  "mounts.sh"
  "media.sh"
  "downloader.sh"
  "scrapers.sh"
  "secrets.sh"
  "env.sh"
  "compose.sh"
  "summary.sh"
)

for module in "${modules[@]}"; do
  curl -fsSL "$BASE_URL/lib/$module" -o "$TMP_DIR/lib/$module"
  [[ -s "$TMP_DIR/lib/$module" ]] || {
    printf '✖  Downloaded module is empty: %s\n' "$module" >&2
    exit 1
  }
done

for module in "${modules[@]}"; do
  # shellcheck disable=SC1090
  source "$TMP_DIR/lib/$module"
done

parse_args "$@"

require_root
require_ubuntu
init_installer_state
init_logging "$LOG_DIR"
print_installer_version
configure_timezone
install_system_dependencies

detect_uid_gid
ensure_docker_installed
setup_docker_group
prepare_filesystem
ensure_riven_rshared_mount

download_compose_files
select_media_server
if [[ "$MEDIA_SERVER" != "external" ]]; then
  start_media_server
fi
collect_media_auth
configure_origin
select_downloader
select_scraper

generate_secrets
build_env_state
write_env_file
sanitize_env_file

start_riven_stack
print_install_summary
if [[ "$MEDIA_SERVER" == "external" ]]; then
  print_external_media_instructions
fi
banner "INSTALL COMPLETE"
