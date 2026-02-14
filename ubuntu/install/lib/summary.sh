#!/usr/bin/env bash

resolve_selected_downloader() {
  if [[ "${RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED:-false}" == 'true' ]]; then
    printf 'Real-Debrid'
    return
  fi

  if [[ "${RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED:-false}" == 'true' ]]; then
    printf 'All-Debrid'
    return
  fi

  if [[ "${RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED:-false}" == 'true' ]]; then
    printf 'Debrid-Link'
    return
  fi

  printf 'Not configured'
}

resolve_selected_scrapers() {
  local selected=()

  [[ "${RIVEN_SCRAPING_TORRENTIO_ENABLED:-false}" == 'true' ]] && selected+=("Torrentio")
  [[ "${RIVEN_SCRAPING_PROWLARR_ENABLED:-false}" == 'true' ]] && selected+=("Prowlarr")
  [[ "${RIVEN_SCRAPING_COMET_ENABLED:-false}" == 'true' ]] && selected+=("Comet")
  [[ "${RIVEN_SCRAPING_JACKETT_ENABLED:-false}" == 'true' ]] && selected+=("Jackett")
  [[ "${RIVEN_SCRAPING_ZILEAN_ENABLED:-false}" == 'true' ]] && selected+=("Zilean")

  if [[ ${#selected[@]} -eq 0 ]]; then
    printf 'Not configured'
    return
  fi

  local joined=''
  local scraper=''
  for scraper in "${selected[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=', '
    fi
    joined+="$scraper"
  done

  printf '%s' "$joined"
}

resolve_media_address() {
  local server_ip="$1"

  if [[ "${MEDIA_SERVER:-managed}" == 'external' ]]; then
    printf 'Existing server (not deployed by installer)'
    return
  fi

  case "${MEDIA_PROFILE:-}" in
    jellyfin)
      printf 'http://%s:8096' "$server_ip"
      ;;
    plex)
      printf 'http://%s:32400/web' "$server_ip"
      ;;
    emby)
      printf 'http://%s:8097' "$server_ip"
      ;;
    *)
      printf 'Unknown'
      ;;
  esac
}

resolve_mount_owner() {
  if [[ -d /mnt/riven ]]; then
    stat -c '%u:%g' /mnt/riven
    return
  fi

  printf '%s:%s' "${TARGET_UID:-unknown}" "${TARGET_GID:-unknown}"
}

print_install_summary() {
  local server_ip='127.0.0.1'
  local riven_access_url='Unknown'
  local media_profile_name='Unknown'
  local media_access_url='Unknown'
  local downloader=''
  local scrapers=''
  local mount_owner=''
  local container_count=0
  local container_ids='None'
  local compose_ids=''

  if hostname -I >/dev/null 2>&1; then
    server_ip="$(hostname -I | awk '{print $1}')"
    server_ip="${server_ip:-127.0.0.1}"
  fi

  riven_access_url="http://$server_ip:3000"
  if [[ "${MEDIA_SERVER:-managed}" == 'external' ]]; then
    media_profile_name="Existing ${EXTERNAL_MEDIA_TYPE:-media} server"
  else
    media_profile_name="${MEDIA_PROFILE:-Unknown}"
  fi
  media_access_url="$(resolve_media_address "$server_ip")"
  downloader="$(resolve_selected_downloader)"
  scrapers="$(resolve_selected_scrapers)"
  mount_owner="$(resolve_mount_owner)"

  if compose_ids="$(docker compose -f "$INSTALL_DIR/docker-compose.yml" ps -q 2>/dev/null)"; then
    if [[ -n "$compose_ids" ]]; then
      container_count="$(printf '%s\n' "$compose_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
      container_ids="$(printf '%s' "$compose_ids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    fi
  fi

  banner 'INSTALL SUMMARY'
  printf 'Riven\n'
  printf '  %-22s %s\n' 'Configured Origin:' "${ORIGIN:-Not set}"
  printf '  %-22s %s\n' 'Access URL:' "$riven_access_url"
  printf '\n'
  printf 'Media Server\n'
  printf '  %-22s %s\n' 'Type:' "$media_profile_name"
  printf '  %-22s %s\n' 'Access Address:' "$media_access_url"
  printf '\n'
  printf 'Providers\n'
  printf '  %-22s %s\n' 'Downloader:' "$downloader"
  printf '  %-22s %s\n' 'Scraper(s):' "$scrapers"
  printf '\n'
  printf 'Storage\n'
  printf '  %-22s %s\n' 'Mount Path:' '/mnt/riven'
  printf '  %-22s %s\n' 'Ownership (UID:GID):' "$mount_owner"
  printf '\n'
  printf 'Docker Stack\n'
  printf '  %-22s %s\n' 'Running Containers:' "$container_count"
  printf '  %-22s %s\n' 'Container IDs:' "$container_ids"
}
