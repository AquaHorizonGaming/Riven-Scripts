# 🗄️ Riven Database Maintenance Tool (PostgreSQL)

This tool provides **safe, interactive maintenance and recovery operations** for the **Riven PostgreSQL database** used in Docker-based Riven deployments.

It is designed to be:
- ✅ Production-safe
- 🧭 Beginner-friendly
- 🔁 Repeatable
- 🛡️ Confirmation-guarded for destructive actions

Works on:
- Ubuntu installs
- Proxmox LXC (unprivileged)
- Any Docker-based Riven setup

---

## 📚 Table of Contents

- [Run the Database Maintenance Tool](#run-the-database-maintenance-tool)
- [What This Tool Does](#what-this-tool-does)
- [Available Operations](#available-operations)
  - [Backup Database](#backup-database)
  - [Vacuum & Analyze](#vacuum--analyze)
  - [Clean Stale / Orphaned Data](#clean-stale--orphaned-data)
  - [Reset Database (Destructive)](#reset-database-destructive)
- [Recommended Usage](#recommended-usage)
- [Restart Services After Maintenance](#restart-services-after-maintenance)
- [Backup Files](#backup-files)
- [Safety Guarantees](#safety-guarantees)
- [When NOT to Use This Tool](#when-not-to-use-this-tool)
- [Summary](#summary)

---

<a id="run-the-database-maintenance-tool"></a>
## ▶️ Run the Database Maintenance Tool

Run this **directly on the system where Riven is installed**:

    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/Riven-Scripts/main/db-tools/riven-db-maintenance.sh | sed 's/\r$//')"

This command automatically fixes Windows CRLF line-ending issues before execution.

---

<a id="what-this-tool-does"></a>
## 🧠 What This Tool Does

This script provides an **interactive menu** for managing the **Riven PostgreSQL database container**.

It automatically:
- Detects the Riven database container
- Verifies PostgreSQL connectivity
- Prevents unsafe or accidental operations
- Prompts before any destructive action

---

<a id="available-operations"></a>
## 🛠 Available Operations

<a id="backup-database"></a>
### 🗂️ Backup Database

Creates a timestamped PostgreSQL dump:
- Safe to run at any time
- Stored locally on the host
- Strongly recommended before any cleanup or reset

---

<a id="vacuum--analyze"></a>
### 🧹 Vacuum & Analyze

Performs standard PostgreSQL maintenance:
- Reclaims unused space
- Improves query performance
- Updates planner statistics

Safe for routine maintenance.

---

<a id="clean-stale--orphaned-data"></a>
### 🧽 Clean Stale / Orphaned Data

Removes broken or unused records caused by:
- Failed scrapes
- Interrupted downloads
- Partial imports

⚠️ Requires confirmation before execution.

---

<a id="reset-database-destructive"></a>
### 🔄 Reset Database (Destructive)

🚨 **THIS WILL DELETE ALL RIVEN DATABASE DATA** 🚨

Includes:
- Scrape history
- Index state
- Download records
- Cached metadata

Use only if:
- The database is corrupted
- Riven cannot recover normally
- You plan to rescrape everything

A backup is **strongly recommended first**.

---

<a id="recommended-usage"></a>
## 🔁 Recommended Usage

### Routine maintenance
1. Backup
2. Vacuum & Analyze
3. Exit

### If Riven behaves incorrectly
1. Backup
2. Clean stale/orphaned data
3. Restart Riven

### Last-resort recovery
1. Backup
2. Reset database
3. Restart Riven
4. Reconfigure and rescrape

---

<a id="restart-services-after-maintenance"></a>
## 🔄 Restart Services After Maintenance

After completing any operation:

    docker restart riven

If you use a media server, restart only what applies:

    docker restart jellyfin
    docker restart plex
    docker restart emby

---

<a id="backup-files"></a>
## 📂 Backup Files

Backups are created with timestamps:

    riven-db-backup-YYYY-MM-DD_HH-MM-SS.sql

Store these somewhere safe before performing destructive actions.

---

<a id="safety-guarantees"></a>
## 🛡️ Safety Guarantees

This tool:
- ❌ Does NOT modify `.env`
- ❌ Does NOT touch media files
- ❌ Does NOT modify mounts
- ❌ Does NOT uninstall containers
- ✅ Uses confirmations for destructive actions
- ✅ Is safe to run multiple times

---

<a id="when-not-to-use-this-tool"></a>
## 🚫 When NOT to Use This Tool

Do **not** use this script to:
- Install Riven
- Update containers
- Fix mount issues
- Replace the installer or updater

Use the appropriate **installer**, **updater**, or **remount-cycle script** instead.

---

<a id="summary"></a>
## ✅ Summary

- Interactive PostgreSQL maintenance for Riven
- Backup-first, safety-focused workflow
- Handles common performance and corruption issues
- Works across Ubuntu and Proxmox LXC deployments
