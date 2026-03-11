# Multistreamer

**Status:** Live and operational
**Server:** Hetzner Cloud (5.78.187.172)
**Cost:** $5.59/month

Stream to Twitch + Kick simultaneously from a single OBS upload.

---

## OBS Setup

```
Service: Custom
Server: rtmp://5.78.187.172/live
Stream Key: livestream
```

---

## Management

All commands run from your local machine:

```bash
# Server management
bash scripts/multistream.sh status     # Server + service status
bash scripts/multistream.sh health     # Quick health check
bash scripts/multistream.sh streams    # Show active streams
bash scripts/multistream.sh logs       # Tail SRS logs
bash scripts/multistream.sh restart    # Restart SRS + Stunnel
bash scripts/multistream.sh deploy     # Push configs to server
bash scripts/multistream.sh update     # Pull latest SRS image
bash scripts/multistream.sh keys       # Update stream keys from .env

# Stream info (set title + game on Twitch and Kick at once)
bash scripts/multistream.sh golive "Playing RE4" --game "Resident Evil 4"
bash scripts/multistream.sh title "New stream title"
bash scripts/multistream.sh game "Just Chatting"
```

Health monitor (auto-restarts downed services):
```bash
bash scripts/monitor.sh
```

---

## API Setup (one-time)

To use `golive`/`title`/`game`, you need API tokens from both platforms:

```bash
bash scripts/auth-setup.sh          # Set up both Twitch + Kick
bash scripts/auth-setup.sh twitch   # Twitch only
bash scripts/auth-setup.sh kick     # Kick only
```

Tokens auto-refresh when they expire.

---

## Server

| Property | Value |
|----------|-------|
| Provider | Hetzner Cloud |
| Location | Hillsboro, OR (us-west) |
| IP | 5.78.187.172 |
| Type | CPX11 (2 vCPU, 4GB RAM, 40GB SSD) |
| Bandwidth | 20 TB/month included |
| Monthly Cost | $5.59 USD |

SSH: `ssh root@5.78.187.172`
Web console: http://5.78.187.172:8080

---

## Platforms

| Platform | Status | Protocol |
|----------|--------|----------|
| Twitch | Active | RTMP direct |
| Kick | Active | RTMPS via Stunnel |
| YouTube | Not connected | - |

---

## Project Structure

```
config/
  srs.conf              # SRS config (ingest + HLS only)
  docker-compose.yml     # Docker setup (SRS + ffmpeg forwarders, keys filled from .env on deploy)
  kick-stunnel.conf      # Stunnel TLS config for Kick
scripts/
  multistream.sh         # Management CLI (status, deploy, golive, title, game)
  monitor.sh             # Health monitor with auto-restart
  auth-setup.sh          # One-time OAuth setup for Twitch + Kick APIs
docs/
  MULTISTREAM_DEPLOYMENT_LOG.md
  MULTISTREAM_SERVICE_STRATEGY.md
.env                     # Stream keys + API tokens (gitignored)
.env.example             # Template
```

---

## Updating Stream Keys

1. Edit `.env` with new keys
2. Run `bash scripts/multistream.sh keys`

---

## Tech Stack

- **SRS 5** (Docker) - RTMP ingest + HLS
- **ffmpeg** (Docker) - Stream forwarding to Twitch and Kick
- **Stunnel** - TLS wrapper for Kick RTMPS
- **vnstat** - Bandwidth tracking
- **UFW** - Firewall
- **Hetzner Cloud** - Infrastructure
