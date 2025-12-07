## Riven Distributables

This repository contains helper scripts and installers for deploying Riven on
different platforms (for example, Proxmox VE and Unraid). Each platform has its
own subdirectory and documentation.

---

## Quick start: Proxmox VE LXC

To create a Debian 12, unprivileged LXC running Riven on a Proxmox VE host,
run this from the **Proxmox host shell**:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/rivenmedia/distributables/main/proxmox/riven.sh)"
```

For detailed Proxmox instructions (requirements, configuration, and troubleshooting),
see:

- [`proxmox/README.md`](proxmox/README.md)

Additional installers (such as Unraid) will live in their own subdirectories
with their own README files.
