## 📚 Table of Contents

- [Install Riven](#installer)
- [Recover Riven Mount & Restart Media](#remount)
- [Uninstall Riven](#uninstaller)
- [Update Riven](#updater)

---

## ▶️ How to run the installer (Ubuntu Script)

Run this command on Ubuntu:

    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/Riven-Scripts/refs/heads/fix-install-script/ubuntu/install/install.sh)"

<a id="installer"></a>
# 🔁 Riven Ubuntu Installer
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
- Use the `.env` file to pass configuration into the containers (mapped to `settings.json`)

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

<a id="remount"></a>
## 🔁 Riven Mount Recovery & Media Restart Tool

This utility safely **resets the Riven mount and restarts media services** without reinstalling or reconfiguring anything.

It is designed for situations where:
- The Riven mount becomes stale
- Media servers see empty libraries
- FUSE/bind mounts fail to release cleanly
- You need to safely cycle storage without rebooting

---

### ▶️ Run this command on Ubuntu

    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/riven-scripts/main/ubuntu/riven-remount-cycle.sh)"

---

### WHAT THIS SCRIPT DOES

- Stops the **Riven Docker container**
- Stops the selected **media server container**
- Actively unmounts the Riven mount path
- Verifies the mount is **fully released**
- Re-attempts unmounting until the kernel confirms it is gone
- Restarts the Riven container
- Waits for the mount to become available
- Starts the media server
- Restarts the media server **after mount stabilization**

---

### INTERACTIVE PROMPTS

During execution, you will be asked to:

- Confirm or change the mount path  
  - Default: `/mnt/riven/mount`
- Select your media server:
  - Plex
  - Jellyfin
  - Emby
  - Custom container name

No configuration files are modified.

---

### IMPORTANT NOTES

- This script **must be run with sudo**
- Safe to run multiple times
- Does **not** remove data
- Does **not** change `.env` or settings
- Does **not** reinstall containers
- Designed for production systems

---

### WHEN TO USE THIS

Use this tool if:
- Media libraries disappear unexpectedly
- Riven appears running but media sees no files
- Mounts do not release after stopping containers
- You want a clean mount reset without rebooting

---

### WHEN NOT TO USE THIS

Do **not** use this script to:
- Install Riven
- Update Riven
- Change configuration
- Replace the installer or updater

---

## ✔️ SAFE RECOVERY COMPLETE

If the script completes without errors:
- The mount is healthy
- Media servers are correctly attached
- No further action is required

---

<a id="uninstaller"></a>
## 🗑️ Riven Ubuntu Uninstaller

This command **completely removes Riven and all related components** installed by the Riven Ubuntu installer.

---

### ▶️ Run this command on Ubuntu

    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/riven-scripts/main/ubuntu/riven-uninstall.sh)"

---

### ⚠️ What this removes

- Riven containers
- Media containers (Jellyfin / Plex / Emby)
- Docker volumes created by Riven
- Riven systemd mount service
- `/opt/riven`
- `/mnt/riven/backend`
- `/mnt/riven/mount`
- `/mnt/riven` (if empty)
- Riven installer logs

> Docker itself is **preserved by default** (you will be prompted).

---

<a id="updater"></a>
## 🔁 Riven Ubuntu Updater

### ▶️ Run this command on Ubuntu

    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/riven-scripts/main/ubuntu/riven-update.sh)"

This command updates **Riven** to the latest available Docker images and optionally updates the configured **media server**.

The updater is **safe by default** and does **not** remove:
- Volumes
- Bind mounts
- Configuration files
- `.env`
- Media libraries

---
