# dietcoke — Home Server Setup

Personal homelab running on a repurposed Lenovo IdeaPad 330S-15IKB laptop running Fedora Server, serving as a self-hosted media, productivity, and automation platform.

---

## Hardware

| | |
|---|---|
| **Device** | Lenovo IdeaPad 330S-15IKB (headless) |
| **CPU** | Intel Core i5-8250U (4C/8T, up to 3.4 GHz) |
| **RAM** | 8 GB DDR4-2400 (2× Samsung M471A5244CB0-CTD SODIMMs) |
| **Network** | ASIX AX88179B USB 3.0 Gigabit Ethernet adapter (Static LAN IP) |

### Storage Layout

| Device | Type | Size | Mount | Notes |
|---|---|---|---|---|
| `nvme0n1` | WD Blue SN550 NVMe | 500 GB | `/` (LVM) | OS, container configs, databases |
| `sda` | Seagate ST1000LM035 SATA HDD | 1 TB | `/mnt/immich` | LUKS-encrypted; Immich photo library |
| `sdb` | Seagate Expansion External HDD STKM2000400 | 2 TB | `/mnt/hdd` | Media library, Borg backup repo |
| `zram0` | zRAM | ~7.6 GB | `[SWAP]` | Compressed RAM swap |

---

## Network Architecture

```
Client devices
     │
     ▼
Pi-hole (DNS, port 53)        ← resolves *.lan → Static IP
     │
     ▼
Caddy (reverse proxy, 80/443) ← TLS via internal CA (self-signed)
     │
     ▼
Services on localhost ports

Remote access: Tailscale (overlay VPN, no port forwarding required)

Torrent traffic: qBittorrent → Gluetun (Cloudflare WARP, WireGuard)
                               └─ routes outbound torrent traffic only
```

- **Reverse proxy**: Caddy with `tls internal` on all service blocks. `import common_headers` snippet applied across all vhosts.
- **DNS**: Pi-hole v6 in Docker. 18 custom `.lan` A records defined in `pihole.toml`. Custom dnsmasq config in `/opt/containers/pihole/etc-dnsmasq.d/`.
- **Remote access**: Tailscale — no router configuration required (router does not support port forwarding or custom DNS).
- **VPN routing**: Gluetun container using Cloudflare WARP over WireGuard. qBittorrent runs inside Gluetun's network namespace. Gluetun control API on port 8000 with API key auth.

---

## Services

| Service | Purpose | Port | Notes |
|---|---|---|---|
| Jellyfin | Media streaming | 8096 | VAAPI hardware transcoding via Intel UHD 620 iGPU (`/dev/dri` passthrough) |
| Immich | Photo library | 2283 | Upload volume on LUKS-encrypted 1 TB HDD |
| Sonarr | TV shows automation | 8989 | |
| Radarr | Movies automation | 7878 | |
| Bazarr | Subtitle automation | 6767 | |
| Prowlarr | Indexer proxy | 9696 | Feeds Sonarr + Radarr |
| qBittorrent | Torrent client | 8080 | Inside Gluetun network namespace |
| Gluetun | VPN container | 8000 (API), 6881 | Cloudflare WARP / WireGuard |
| Jellyseerr | Media request UI | 5055 | |
| Pi-hole | DNS + ad blocking | 53, 8081 | v6 unified config in `pihole.toml` |
| Caddy | Reverse proxy | 80, 443 | |
| Vaultwarden | Password manager | 443 (via Caddy) | |
| Kavita | Ebook/manga reader | 5000 | |
| Syncthing | File sync | 8384 | Obsidian vault sync across devices |
| Glance | Dashboard | 1234 | Custom widgets (see below) |
| Uptime Kuma | Service monitoring | 3001 (via Caddy) | |
| DIUN | Docker image update alerts | — | Telegram notifications |
| Tailscale | Remote access | — | System-level |
| Crafty Controller | Minecraft server management | 8443 | PaperMC 26.1.2 |
| Immich PostgreSQL | Database for Immich | 5432 (internal) | pgvector/pg15 |
| Immich Redis | Cache for Immich | 6379 (internal) | |
| Immich Typesense | Search for Immich | 8108 (internal) | |
| f1_api | F1 schedule/results API | 4463 | Third-party image |
| f1-map-proxy | F1 track map renderer | 4464 | Custom container — see below |

---

## Custom / Original Work

### Automation Scripts

**`immich-backup.sh`** — Borg Backup wrapper
- Backs up `/mnt/immich` to `/mnt/hdd/immich-backup`
- Pre-flight checks: verifies both source and destination are mounted before proceeding
- Runs `borg create` → `borg prune` (7d/4w/6m retention) → `borg compact`
- Sends Telegram notification on success or failure
- Triggered by systemd timer at 3:00 AM

**`smartd-telegram.sh`** — SMART alert notifier
- Called by `smartd` on any SMART failure: -M exec /usr/local/bin/smartd-telegram.sh
- Sends disk device name, SMART message, hostname, and timestamp to Telegram
- Covers internal NVMe and SATA HDD (`smartd` only; USB HDD uses separate cron approach — see below)
- Recieves alert details via smartd environment variables: SMARTD_DEVICE, SMARTD_MESSAGE, SMARTD_DEVICETYPE, SMARTD_FAILTYPE

**`ssh-telegram.sh`** — SSH login/logout notifier
- PAM-triggered on `open_session` / `close_session`
- Sends login or logout event with username, source IP, hostname, and timestamp to Telegram

**`mc-watch.sh`** — Minecraft-triggered swap reset
- Polls Docker every 10 seconds for the `paper.jar` Java process inside the Crafty container
- When Minecraft stops (process disappears), waits 30 seconds then calls `reset-swap.sh`
- Guards against false triggers using a `/tmp/mc-was-running` sentinel file
- Rationale: Minecraft causes significant swap accumulation (due to limited RAM on my system); resetting swap after mc server stops, reclaims memory from SWAP back into RAM cleanly

**`reset-swap.sh`** — zRAM swap reset
- Runs `swapoff`, writes `1` to `/sys/block/zram0/reset`, then restarts `systemd-zram-setup@zram0.service`
- Currently has a known issue: zram device may be busy mid-sequence (unresolved)

### Custom Docker Container: `f1-map-proxy`

- Built from source
- Proxies F1 track vector SVGs from `f1laps/f1-track-vectors` and renders them to PNG using `cairosvg`
- Exists because Glance dashboard cannot render SVGs inline — PNG conversion required
- Consumed by Glance's custom F1 widgets

### Glance Dashboard Customisations

- Custom F1 widgets pulling from Jolpica API (`api.jolpi.ca/ergast/f1/`) and the local `f1_api` container
- Track map display using rendered PNGs from the custom `f1-map-proxy`
- Gluetun VPN status widget showing current public IP (via Gluetun control API on port 8000)
- Dashboard config in `/home/admin/glance/config/`
- Source and deployment instructions: [f1-map-proxy](https://github.com/bingchilling480/f1-map-proxy)

### USB HDD SMART Monitoring Workaround

- The Seagate Expansion enclosure's UAS kernel driver conflicts with `smartd`'s standard SAT probing
- Resolved by abandoning `smartd` for the USB drive and using a cron job that runs `smartctl -H -d scsi` directly
- On failure, sends a Telegram alert via `curl` inline
- Example of the cron job: 
```
0 3 * * * smartctl -H -d scsi /dev/disk/by-id/<USB_DRIVE_ID> | grep -q "SMART Health Status: OK" || curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d chat_id="$TELEGRAM_CHAT_ID" -d text="SMART ALERT: Seagate 2TB health check FAILED on $(hostname) at $(date)"
```

---

## Notable Problems Debugged

### Sonarr/Prowlarr Indexer Timeouts

**Problem:** Indexers repeatedly enter a 6-hour disabled state in Sonarr. Manual "Test Indexers" click in Sonarr UI was the only recovery.

**Root cause:** Sonarr fires all indexers simultaneously per episode per search. For example, with 2 episodes × 4 indexers = 8 concurrent HTTP requests in rapid succession, indexers return HTTP 429 (rate limited). Accumulated failures cross Sonarr's disable threshold.

**Fix applied:** Raise RSS Sync Interval to 60–120 minutes. Not confirmed fully resolved.

---

### USB HDD Device Name Drift

**Problem:** External USB HDD changes device name (`sda` → `sdc` etc.) between reboots, causing Docker bind mounts to reference stale paths.

**Root cause:** Linux assigns block device names dynamically at boot; USB drives are not guaranteed a stable name.

**Fix:** Mount by UUID in `/etc/fstab`. Docker bind mounts then always resolve to the correct path regardless of device name. (a quick restart of the containers after a reboot also fixes the issue)

---

### Crafty Monitoring in Glance Broken

**Problem:** Glance cannot verify Crafty's self-signed TLS certificate.

**Root cause:** Crafty's cert has no IP SANs — only covers `localhost`, `*.local`, and the container hostname. Glance connects via IP, which isn't in the SAN list.

**Fix:** Not resolved. A possible fix might be regenerating Crafty's cert with the server IP as a SAN, or proxying Crafty through Caddy with a `.lan` hostname.

---

## Directory Structure

```
/opt/containers/
├── bazarr/
├── book-reader/       # Kavita
├── crafty/
├── diun/
├── gluetun/           # Note: directory on disk is spelled 'glueton'
├── immich/
├── jellyfin/
├── jellyseerr/
├── monitoring/
│   └── uptime-kuma/
├── pihole/
│   ├── etc-pihole/
│   └── etc-dnsmasq.d/
├── prowlarr/
├── radarr/
├── sonarr/
├── syncthing/
└── vaultwarden/

/opt/caddy/            # Caddy compose + Caddyfile

/home/admin/glance/
├── docker-compose.yml
├── config/
├── assets/
└── f1api/
    ├── docker-compose.yml
    └── f1-map-proxy/  # Custom container (source)

/usr/local/bin/        # Custom automation scripts
```
