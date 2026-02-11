#!/usr/bin/env bash

download_compose_files() {
  banner 'Docker Compose Files'
  cd "$INSTALL_DIR"
  curl -fsSL "$MEDIA_COMPOSE_URL" -o docker-compose.media.yml
  curl -fsSL "$RIVEN_COMPOSE_URL" -o docker-compose.yml
  ok 'Compose files downloaded'
}

start_media_server() {
  banner 'Starting Media Server'

  docker compose -f docker-compose.media.yml --profile "$MEDIA_PROFILE" up -d
  ok 'Media server started'

  SERVER_IP="$(hostname -I | awk '{print $1}')"

  echo
  echo '➡️  Open your media server in a browser:'
  echo "👉  http://$SERVER_IP:$MEDIA_PORT"
  echo
  echo '• Complete setup'
  echo '• Create admin user'
  echo '• Generate API key / token'
  echo
  read -r -p 'Press ENTER once media server setup is complete...'
}

start_riven_stack() {
  banner 'Starting Riven'
  cd "$INSTALL_DIR"
  docker compose up -d
  ok 'Riven started'
}
