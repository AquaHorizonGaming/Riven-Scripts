# Riven Scripts

This repository contains official helper scripts and installers for deploying
**Riven** on supported platforms.

Each platform has its own subdirectory with a dedicated installer and
documentation.

---

## Quick Start

### Proxmox VE (LXC)

To create a **Debian 12 unprivileged LXC** configured to run Riven on a
**Proxmox VE host**, run the following command **from the Proxmox host shell**:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/AquaHorizonGaming/Riven-Scripts/main/proxmox/install.sh)"
```

This installer handles:
- LXC creation and configuration
- Docker + FUSE setup
- Required mount propagation for Riven
- Optional GPU passthrough support

Full Proxmox documentation:
- [`proxmox/README.md`](proxmox/README.md)

---

### Ubuntu (Bare Metal / VM)

To install Riven directly on an **Ubuntu system** (VM or bare metal),
run the installer below:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/AquaHorizonGaming/Riven-Scripts/main/ubuntu/install.sh)"
```

This installer handles:
- System dependency installation
- Docker and Docker Compose setup
- Riven service preparation and directory layout

Full Ubuntu documentation:
- [`ubuntu/readme.md`](ubuntu/readme.md)

---

## Repository Structure

```text
Riven-Scripts/
├── proxmox/        # Proxmox VE LXC installer + docs
├── ubuntu/         # Ubuntu installer + docs
└── README.md       # This file
```

---

## Notes

- Each platform is self-contained and documented independently
- Always follow the README inside the platform directory for configuration
  and troubleshooting
- Additional platforms can be added later using the same structure
