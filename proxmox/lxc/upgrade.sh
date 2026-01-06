#!/usr/bin/env bash
set -euo pipefail

cd /srv/riven/app

echo "Stopping Riven stack..."
docker compose down

echo "Pulling latest images..."
docker compose pull

echo "Starting Riven stack..."
docker compose up -d --remove-orphans

echo "Cleaning old images..."
docker image prune -f

echo "Upgrade complete"
