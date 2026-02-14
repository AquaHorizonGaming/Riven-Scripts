# AGENTS.md — Repository Intelligence for `Riven-Scripts`

This document is a **ground-truth operating guide** for coding agents working in this repository.
It is intentionally explicit to reduce hallucinations and unsafe edits.

---

## 1) Repository Overview

### Project purpose
`Riven-Scripts` provides shell-based automation for deploying and maintaining the Riven stack across:
- Ubuntu hosts (direct Docker deployment).
- Proxmox hosts (provisioning an unprivileged Debian 12 LXC, then deploying Dockerized Riven inside it).
- Database maintenance helper scripts for an existing Riven installation.

The top-level README positions this as the official helper/install script repo for Riven with platform-specific folders.

### Branch purpose
The Ubuntu installer bootstrap (`ubuntu/install/install.sh`) hardcodes:
- `default_branch="fix-install-script"`

This indicates this branch is intended to ship/fetch install modules from `fix-install-script` for the Ubuntu installer pipeline.

### Full tracked tree (source files)

```text
Riven-Scripts/
├── README.md
├── AGENTS.md  <-- this file
├── db-tools/
│   ├── db_pegger_9000.sh
│   ├── readme.md
│   └── riven-db-maintenance.sh
├── proxmox/
│   ├── README.md
│   ├── changelog.md
│   └── lxc/
│       ├── docker-compose.yml
│       ├── lxc-bootstrap.sh
│       ├── lxc-create.sh
│       ├── riven-install.sh
│       └── upgrade.sh
└── ubuntu/
    ├── docker-compose.media.yml
    ├── docker-compose.yml
    ├── install.sh
    ├── install/
    │   ├── install.sh
    │   └── lib/
    │       ├── args.sh
    │       ├── compose.sh
    │       ├── docker.sh
    │       ├── downloader.sh
    │       ├── env.sh
    │       ├── filesystem.sh
    │       ├── helpers.sh
    │       ├── logging.sh
    │       ├── mounts.sh
    │       ├── media.sh
    │       ├── root.sh
    │       ├── scrapers.sh
    │       ├── secrets.sh
    │       ├── seer.sh
    │       ├── summary.sh
    │       └── users.sh
    ├── readme.md
    ├── riven-remount-cycle.sh
    ├── riven-uninstall.sh
    └── riven-update.sh
```

### Platform separation
- `ubuntu/`: interactive Ubuntu installer + updater/uninstaller/remount scripts + compose files.
- `proxmox/`: host-side Proxmox documentation/changelog and LXC-side install assets.
- `db-tools/`: direct `docker exec` PostgreSQL maintenance scripts for running deployments.

---

## 2) Installer Architecture (Ubuntu)

### Entry points
- Public wrapper: `ubuntu/install.sh` (contains only shebang; no logic).
- Actual bootstrap entrypoint: `ubuntu/install/install.sh`.

### Module system (`ubuntu/install/lib/`)
`install/install.sh` downloads each module from GitHub raw URL into a temp dir, verifies non-empty, then `source`s in a fixed order.

Module load order:
1. `helpers.sh`
2. `logging.sh`
3. `root.sh`
4. `args.sh`
5. `users.sh`
6. `docker.sh`
7. `filesystem.sh`
8. `mounts.sh`
9. `media.sh`
10. `downloader.sh`
11. `scrapers.sh`
12. `seer.sh`
13. `secrets.sh`
14. `env.sh`
15. `compose.sh`
16. `summary.sh`

### Execution order
After loading modules:
1. `parse_args`
2. `require_root`
3. `require_ubuntu`
4. `init_installer_state`
5. `init_logging`
6. `print_installer_version`
7. `configure_timezone`
8. `install_system_dependencies`
9. `detect_uid_gid`
10. `ensure_docker_installed`
11. `setup_docker_group`
12. `prepare_filesystem`
13. `ensure_riven_rshared_mount`
14. `download_compose_files`
15. `select_media_server`
16. `start_media_server` (only if managed media selected)
17. `select_seer_install`
18. `setup_seer` (only if Seer enabled)
19. `collect_media_auth`
20. `configure_origin`
21. `select_downloader`
22. `select_scraper`
23. `generate_secrets`
24. `build_env_state`
25. `write_env_file`
26. `sanitize_env_file`
27. `start_riven_stack`
28. `print_install_summary`
29. `print_external_media_instructions` (only for external media)
30. final banner

### Flow diagram (deterministic)

```text
Preflight (root/os/logging/timezone/deps/user/docker/fs/mount)
  -> Compose download
  -> Media selection
     -> Managed media? start selected media profile
  -> Optional Seer prompt
     -> If yes: start seer and print instructions
  -> Media auth collection (managed only)
  -> ORIGIN prompt (reverse proxy optional)
  -> Downloader selection (required)
  -> Scraper selection (required)
  -> Secret generation (POSTGRES/AUTH/BACKEND_API_KEY)
  -> Env state build (media updater mapping)
  -> .env write + sanitize
  -> docker compose up -d (Riven stack)
  -> Summary + optional external media instructions
```

---

## 3) Environment System Documentation

### What `ubuntu/install/lib/env.sh` does
- Initializes installer globals (`INSTALL_DIR`, `BACKEND_PATH`, URLs, flags).
- Handles timezone detection and user confirmation.
- Builds updater-related env variables from selected media profile.
- Writes `.env` in a single heredoc operation.
- Normalizes some optional booleans (`false` -> empty string).
- Runs a post-write sanitizer for malformed multiline quoted values.

### Registration model
There is **no key-by-key env registration helper** (no `register_env`/`set_env` function). The system is batch-write:
- Variables are assigned in shell globals by earlier modules.
- `write_env_file` writes all keys in one heredoc.

### Duplicate prevention
- No explicit duplicate-key detection exists.
- Duplication is implicitly avoided because `.env` is overwritten from scratch (`cat > "$INSTALL_DIR/.env"`).

### Finalization
- `write_env_file`: creates `.env`.
- `sanitize_env_file`: rewrites to `.env.fixed` then `mv` back to `.env`.
- Compose consumes this file via `env_file: [.env]` and `${VAR}` interpolation.

### Variable naming conventions
- Uppercase snake case for all exported/runtime vars.
- Riven-specific keys are prefixed by domain:
  - `RIVEN_UPDATERS_*`
  - `RIVEN_DOWNLOADERS_*`
  - `RIVEN_SCRAPING_*`
  - `RIVEN_CONTENT_*`
- Secrets/general keys:
  - `POSTGRES_*`, `BACKEND_API_KEY`, `AUTH_SECRET`, `ORIGIN`, `TZ`.

### Critical variables (actual names in repo)
- `BACKEND_API_KEY` (mapped to `RIVEN_API_KEY` in compose).
- `AUTH_SECRET`.
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`.
- `ORIGIN`, `TZ`.
- `RIVEN_CONTENT_OVERSEER_API_KEY` (Seer key injection).
- `RIVEN_CONTENT_OVERSEER_ENABLED`.

**Important:** `RIVEN_API_KEY` is a container env variable sourced from `.env` key `BACKEND_API_KEY`; `.env` does not contain `RIVEN_API_KEY` directly.

### When env write occurs
In Ubuntu install flow, `.env` is written only after all interactive prompts (media auth, origin, downloader, scraper, secrets).

### “env.sh helpers” status
No standalone `env.sh` helper utility file exists outside `ubuntu/install/lib/env.sh`.
The helper-like behavior is embedded in functions inside that module (`build_env_state`, `normalize_optional_env_values`, `write_env_file`, `sanitize_env_file`).

---

## 4) Service Map

### Ubuntu compose services (`ubuntu/docker-compose.yml`)

#### `riven-db`
- Image: `postgres:17-alpine`
- Port exposure: none (internal only).
- Healthcheck: `pg_isready -U ${POSTGRES_USER}`
- Required env: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- Volume: `riven-pg-data`
- Start order dependency target for `riven`.

#### `riven`
- Image: `spoked/riven:dev`
- Ports: `8080:8080`
- Depends on: `riven-db` healthy
- Requires FUSE: `/dev/fuse`, `SYS_ADMIN`, apparmor unconfined
- Key env dependencies: database URL, `RIVEN_API_KEY` (from `BACKEND_API_KEY`), updater/downloader/scraper vars
- Volumes: `/mnt/riven/backend:/riven/data`, `/mnt/riven/mount:/mount:rshared,z`

#### `riven-frontend`
- Image: `spoked/riven-frontend:dev`
- Ports: `3000:3000`
- Uses `BACKEND_URL=http://riven:8080`
- Requires: `BACKEND_API_KEY`, `AUTH_SECRET`, `ORIGIN`, `TZ`

#### Network/volume
- Network: `media` bridge
- Volumes: `riven-frontend-data`, `riven-pg-data`

### Ubuntu media compose (`ubuntu/docker-compose.media.yml`)
- `jellyfin` profile `jellyfin`: `8096:8096`
- `plex` profile `plex`: `32400:32400`
- `emby` profile `emby`: `8097:8096`
- All mount `/mnt/riven/mount:/media:ro`

### Optional Seer (from main Ubuntu compose)
- Installer launches via `docker compose up -d seer`.
- User-facing URL reported as `http://<host-ip>:5055`.
- Env integration: `RIVEN_CONTENT_OVERSEER_ENABLED` + `RIVEN_CONTENT_OVERSEER_API_KEY` in `.env`.

### Proxmox LXC compose (`proxmox/lxc/docker-compose.yml`)
Services:
- `riven-db` (Postgres)
- `riven` (`8080:8080`, FUSE)
- `riven-frontend` (`3000:3000`)
- optional media profiles: `jellyfin` (`8096:8096`), `plex` (`network_mode: host`), `emby` (`8097:8096`)

Path base differs from Ubuntu:
- Backend: `/srv/riven/backend`
- Mount: `/srv/riven/mount`

### Start order patterns
- Ubuntu installer starts managed media first (if chosen), optionally Seer, then full Riven stack.
- Compose-level ordering enforced with `depends_on` health checks for DB → Riven.

---

## 5) Optional Modules / Conditional Features

### Ubuntu optional paths
1. **External media server mode**
   - Chosen in media selection (`MEDIA_SERVER='external'`).
   - Skips media container startup.
   - Skips media auth prompt data collection.
   - Prints post-install guidance for Plex/Emby/Jellyfin integration.

2. **Seer installation**
   - Prompt: `select_seer_install` (required yes/no selection).
   - If enabled: captures Seer API key and starts `seer` service.
   - If disabled: key is blank and enabled flag false.

3. **Media update in updater**
   - `ubuntu/riven-update.sh` asks whether to update media compose stack.

### Isolation / side effects
- Feature toggles are boolean/string env values consumed by compose/runtime.
- Optional services are gated by explicit prompt choices.
- External media mode avoids provisioning media containers.

---

## 6) Safe Modification Rules for Future Agents

1. **Do not hand-edit generated `.env` logic ad hoc.**
   - Update `write_env_file` and related builders together.
2. **Preserve installer execution order** in `ubuntu/install/install.sh` unless explicitly redesigning flow.
3. **Do not bypass rshared mount enforcement** (`ensure_riven_rshared_mount` / systemd unit behavior).
4. **Do not silently auto-generate or replace user-provided API tokens** except where code already generates internal secrets (`BACKEND_API_KEY`, DB password, `AUTH_SECRET`).
5. **Maintain idempotency expectations**:
   - Docker/install checks should remain safe on re-run.
   - Existing compose/.env assumptions must not be broken.
6. **Avoid duplicate env key introduction** in `write_env_file`.
7. **Keep compose ordering and health dependencies intact** (`riven-db` health before `riven`).
8. **Do not modify media selection semantics** without updating downstream env mapping and docs.
9. **Treat prompt text as UX contract**; abrupt prompt changes can break user guidance.
10. **Respect platform boundaries**:
   - Ubuntu paths `/opt/riven` + `/mnt/riven/*`
   - Proxmox/LXC paths `/srv/riven/*`

---

## 7) Install Flow Specification (Exact)

Ubuntu deterministic flow:
1. Media selection (managed Plex/Emby/Jellyfin vs external).
2. (If managed) media service startup with selected compose profile.
3. External API registration prompts:
   - Media API/token prompt (managed only).
   - Downloader API key prompt (required choice among 3).
   - Scraper URL/API prompt (required choice among 5; API key only for Prowlarr/Jackett).
4. Optional Seer decision and Seer API token capture.
5. Token handling:
   - User-supplied: media/downloader/scraper/seer keys.
   - Generated: DB password, auth secret, backend api key.
6. Env registration:
   - Build updater flags from media profile.
   - Write complete `.env` file.
   - Sanitize `.env` formatting.
7. Docker compose execution:
   - `docker compose up -d` for main stack.
8. Finalization:
   - Print summary URLs/status.
   - Print external-media instructions if relevant.

---

## 8) Error Handling Behavior

### Ubuntu installer framework
- Global: `set -euo pipefail` in entrypoint.
- Logging module installs `trap ... ERR` → immediate failure output with line number.
- `fail()` prints error and exits non-zero.

### If Docker fails
- Preflight checks fail early (`ensure_docker_installed`, compose existence/runtime checks).
- Any failing compose command exits script via `set -e`/`fail` path.

### If env generation fails
- Invalid timezone or missing required values invoke `fail`.
- Secrets generation validates API key length/pattern and fails if invalid.
- Failed write/sanitize steps terminate installer.

### If user declines optional modules
- Seer: set disabled state and continue.
- Media updates in updater: skipped cleanly.
- External media mode: no media service deployment; prints manual instructions.

### Re-run behavior
- Installer is partially idempotent (dependency checks, Docker checks, directory creation).
- It rewrites `.env` each run.
- Compose `up -d` is naturally repeatable.
- Uninstaller removes created assets and optionally Docker engine.

---

## 9) Project Conventions

### Shell style
- Most scripts use `#!/usr/bin/env bash` + `set -euo pipefail`.
- Some db tools use `#!/bin/bash` and weaker style consistency.
- Function-based procedural scripts; no classes/frameworks.

### Prompt formatting
Common patterns:
- Section banners using heavy separators.
- Numbered option menus.
- Explicit “Select ONE” wording where required.
- Security note for hidden token input.

### Naming conventions
- Constants uppercase (e.g., `INSTALL_DIR`, `MOUNT_PATH`).
- Functions lower_snake_case.
- Service names fixed: `riven`, `riven-db`, `riven-frontend`, `seer`, `jellyfin`, `plex`, `emby`.

### Indentation
- Ubuntu installer modules use two spaces inside functions.
- Legacy db scripts commonly use four spaces.

### Compose invocation patterns
- Main stack: `docker compose up -d`, `docker compose pull`, `docker compose down`.
- Media stack: `docker compose -f docker-compose.media.yml ...` with profile for install-time start.
- Proxmox optional media: `docker compose --profile <name> up -d`.

### IP detection
- Scripts generally resolve host IP using:
  - `hostname -I | awk '{print $1}'`

### Service startup pattern
- Ubuntu install: optional media first, then optional Seer, then main Riven stack.
- Compose-level DB health gate before Riven start.

---

## Shell Scripts Inventory (all tracked)

- `ubuntu/riven-remount-cycle.sh`
- `ubuntu/riven-update.sh`
- `ubuntu/riven-uninstall.sh`
- `ubuntu/install.sh` (stub)
- `ubuntu/install/install.sh`
- `ubuntu/install/lib/*.sh` (16 modules)
- `proxmox/lxc/lxc-create.sh`
- `proxmox/lxc/lxc-bootstrap.sh`
- `proxmox/lxc/riven-install.sh`
- `proxmox/lxc/upgrade.sh`
- `db-tools/riven-db-maintenance.sh`
- `db-tools/db_pegger_9000.sh`

## Docker Compose Files Inventory
- `ubuntu/docker-compose.yml`
- `ubuntu/docker-compose.media.yml`
- `proxmox/lxc/docker-compose.yml`

---

## Notes on Ambiguities / Non-obvious Facts

1. `ubuntu/install.sh` currently has only a shebang and no bootstrap logic.
2. Top-level README references `proxmox/install.sh`, but that file is not present in tracked files.
3. `db-tools/riven-db-maintenance.sh` is a show/episode state manipulation workflow (not a generic vacuum/reset menu despite `db-tools/readme.md` wording).
4. No dedicated shared `env.sh` utility exists outside Ubuntu installer module.

