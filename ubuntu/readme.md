## ▶️ How to run the installer (Ubuntu Script)

Run this command on Ubuntu:
``` bash
    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/install.sh)"
```

# Riven Ubuntu Installer

This installer deploys **Riven** on Ubuntu using Docker and Docker Compose with a fully interactive guided setup.

---

## SUPPORTED SYSTEMS

- Ubuntu Server
- Ubuntu Desktop
- Virtual Machines
- Headless servers
- Advanced WSL setups

---

## WHAT THIS SCRIPT DOES

### SYSTEM & DOCKER
- Installs Docker and Docker Compose ONLY if missing
- Configures Docker to use IPv4 only (IPv6 disabled inside Docker only)
- Sets reliable DNS defaults for containers

---

### FILESYSTEM & MOUNTS

Creates and manages the following paths:

    /opt/riven
     ├─ docker-compose.yml
     └─ .env

    /mnt/riven/backend
     ├─ Riven backend data
     └─ settings.json (auto-generated)

    /mnt/riven/mount
     └─ Media library (movies, TV, anime)

- Configures a systemd mount service
- Ensures /mnt/riven/mount is bind-mounted as rshared
- This behavior is REQUIRED for Riven to function

---

## RIVEN DEPLOYMENT (AUTOMATED)

The installer performs a fully interactive configuration.

### DURING INSTALL YOU WILL BE PROMPTED TO:
- Select a Downloader (e.g. Real-Debrid)
- Select a Scraper
- Select a Media Server:
  - Plex
  - Jellyfin
  - Emby
- Enter required API keys / tokens

### THE SCRIPT WILL:
- Generate a secure `.env` file
- Download the `docker-compose.yml`
- Pull all required container images
- Start containers with retry logic
- Verify that all services are running
- Use the `.env` file to pass configuration into the containers 
- (mapped to `settings.json`)

NO manual configuration is required after install.

---

## IMPORTANT CHANGE

OLD BEHAVIOR:
- Manual editing of /mnt/riven/backend/settings.json was required

NEW BEHAVIOR:
- All configuration is handled during the installer
- Riven starts fully configured
- Scraping and media integration work immediately

---

## ACCESSING THE FRONTEND

After installation completes, the script prints:

    http://<SERVER_IP>:3000
               Or
        http://<domain>
---

## IMPORTANT PATHS

- Docker Compose: /opt/riven/docker-compose.yml
- Environment file: /opt/riven/.env
- Backend config: /mnt/riven/backend/settings.json
- Media library: /mnt/riven/mount

---

## TROUBLESHOOTING

Check running containers:

    docker ps

Restart everything:

    cd /opt/riven
    docker compose down
    docker compose up -d

View backend logs:

    docker logs riven

---

## INSTALL COMPLETE

If containers are running and no errors are shown:
- Riven is installed
- Media servers are connected
- Scraping is active
- No further setup is required

