# Riven Proxmox LXC Installer (Docker)

## ▶️ Run on Proxmox host

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/proxmox/install.sh)"
```
## What it does
- Creates an **unprivileged Debian 12** LXC
- Enables **nesting + keyctl + fuse**
- Passes **/dev/fuse** into the CT
- Optionally passes **/dev/dri** (GPU) if you select it
- Installs **Docker + Docker Compose plugin** inside the CT
- Deploys **Riven backend + frontend + PostgreSQL**
- Supports optional media servers via compose profiles:
  - Jellyfin / Plex / Emby

## Access
- Backend: `http://<CT-IP>:8080`
- Frontend: `http://<CT-IP>:3000`

Get CT IP:
```bash
pct exec <CTID> -- hostname -I
```

## Required configuration
🚨 **YOU MUST CONFIGURE A MEDIA SERVER OR RIVEN WONT START** 🚨

Edit:
- `/srv/riven/backend/settings.json`

Then restart:
```bash
pct exec <CTID> -- docker restart riven
```

## Optional media servers
Inside the CT:
```bash
cd /srv/riven/app
docker compose --profile jellyfin up -d
docker compose --profile plex up -d
docker compose --profile emby up -d
```

## Upgrade
Inside the CT:
```bash
/srv/riven/app/upgrade.sh
```
