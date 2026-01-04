```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/install.sh)"

# Riven Ubuntu Installer

This script installs and configures Riven on Ubuntu using Docker and Docker Compose.

SUPPORTED SYSTEMS
- Ubuntu Server
- Ubuntu Desktop
- Virtual Machines
- Headless servers
- Advanced WSL setups

WHAT THIS SCRIPT DOES

SYSTEM & DOCKER
- Installs Docker and Docker Compose ONLY if missing
- Configures Docker to use IPv4 only (IPv6 disabled inside Docker only)
- Sets reliable DNS for containers

FILESYSTEM & MOUNTS
Creates the following directories:
- /opt/riven
  - docker-compose.yml
  - .env
- /mnt/riven/backend
  - Riven backend data
  - settings.json configuration
- /mnt/riven/mount
  - ALL movies, TV shows, and anime live here

Sets up a systemd service to ensure /mnt/riven/mount is bind-mounted as rshared.
This is REQUIRED for Riven to function.

RIVEN DEPLOYMENT
- Downloads docker-compose.yml automatically
- Generates a secure .env file
- Pulls and starts all containers
- Retries containers that fail to start (especially frontend)
- Verifies containers are running

REQUIRED CONFIGURATION (DO NOT SKIP)

AFTER INSTALL YOU MUST EDIT:
- /mnt/riven/backend/settings.json

YOU MUST:
- Add at least ONE scraper
- Configure at least ONE media server (Plex, Jellyfin, or Emby)

IF YOU DO NOT DO THIS:
- Containers WILL appear healthy
- NO content will load
- Scraping will silently fail

RIVEN WILL NOT WORK UNTIL THIS IS CONFIGURED.

ACCESSING THE FRONTEND

After installation completes, the script will print:
- http://<SERVER_IP>:3000

IMPORTANT PATHS SUMMARY

Docker Compose:
- /opt/riven/docker-compose.yml

Environment file:
- /opt/riven/.env

Backend configuration:
- /mnt/riven/backend/settings.json

Media library location:
- /mnt/riven/mount

TROUBLESHOOTING

Check running containers:
- docker ps

Restart everything:
- cd /opt/riven
- docker compose down
- docker compose up -d

View backend logs:
- docker logs riven
```
