# Multistreamer

Stream to Twitch + Kick simultaneously from a single OBS output. Self-hosted on any VPS for ~$5/month instead of paying Restream $16-39/month.

## How It Works

```
OBS → Your Server (SRS) → ffmpeg → Twitch (RTMP)
                        → ffmpeg → Stunnel → Kick (RTMPS)
```

OBS sends one RTMP stream to your server. SRS receives it. Two ffmpeg containers pull from SRS and push to each platform. Stunnel wraps the Kick stream in TLS (Kick requires RTMPS).

## Requirements

- A VPS with Docker (tested on Hetzner CPX11 — 2 vCPU, 4GB RAM, ~$5.59/month)
- Stream keys from Twitch and Kick
- Python 3 (for API commands)
- Stunnel (for Kick RTMPS)

## Setup

### 1. Server

SSH into your VPS and install Docker, then set up stunnel:

```bash
# Install stunnel
apt install stunnel4 -y
systemctl enable stunnel4
```

Copy `config/kick-stunnel.conf` to `/etc/stunnel/kick.conf` on your server. Edit the `connect` line to point to your Kick RTMP ingest server.

### 2. Configure

```bash
cp .env.example .env
```

Fill in your `.env`:
- `SERVER_IP` — your VPS IP
- `TWITCH_STREAM_KEY` — from twitch.tv/dashboard/settings
- `KICK_STREAM_KEY` — from kick.com/dashboard/settings

### 3. Deploy

```bash
bash scripts/multistream.sh deploy
```

This substitutes your stream keys into the docker-compose config, uploads everything to the server, and starts the containers.

### 4. OBS

```
Service: Custom
Server:  rtmp://YOUR_SERVER_IP/live
Key:     livestream
```

Hit Start Streaming. Both platforms go live.

## API Setup (Optional)

Set stream titles and game/category on both platforms simultaneously.

### Register Apps

**Twitch:** [dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps)
- Redirect URL: `http://localhost:3000`
- Category: Broadcaster Suite
- Scope needed: `channel:manage:broadcast`

**Kick:** [dev.kick.com](https://dev.kick.com)
- Redirect URI: `http://localhost:3000`
- Scope needed: `channel:write`
- Kick uses OAuth 2.1 with PKCE (S256)

### Authenticate

```bash
bash scripts/auth-setup.sh          # Both platforms
bash scripts/auth-setup.sh twitch   # Twitch only
bash scripts/auth-setup.sh kick     # Kick only
```

Tokens are saved to `.env` and auto-refresh on expiry.

## Commands

```bash
# Server management
bash scripts/multistream.sh status     # Server + service status
bash scripts/multistream.sh health     # Quick health check (exit 0 = healthy)
bash scripts/multistream.sh streams    # Active streams via SRS API
bash scripts/multistream.sh logs       # Tail SRS logs
bash scripts/multistream.sh restart    # Restart all services
bash scripts/multistream.sh deploy     # Push configs and restart
bash scripts/multistream.sh update     # Pull latest SRS image
bash scripts/multistream.sh keys       # Re-deploy with updated stream keys

# Stream metadata (requires API setup)
bash scripts/multistream.sh golive "Title" --game "Game Name"
bash scripts/multistream.sh title "New Title"
bash scripts/multistream.sh game "Just Chatting"

# Health monitor (auto-restarts downed services)
bash scripts/monitor.sh
```

## Project Structure

```
config/
  docker-compose.yml     # SRS + 2x ffmpeg forwarders (keys templated from .env)
  srs.conf               # SRS ingest config
  kick-stunnel.conf      # Stunnel TLS config for Kick RTMPS
scripts/
  multistream.sh         # Main CLI
  auth-setup.sh          # One-time OAuth setup for Twitch + Kick
  monitor.sh             # Health monitor with auto-restart
.env.example             # Template
```

## Adding YouTube

Add a third ffmpeg service to `docker-compose.yml`:

```yaml
  forward-youtube:
    image: jrottenberg/ffmpeg:4.4-alpine
    container_name: multistream-youtube
    restart: unless-stopped
    depends_on:
      - srs
    network_mode: host
    command: >
      -hide_banner -loglevel warning
      -i rtmp://127.0.0.1:1935/live/livestream
      -c copy -f flv
      rtmp://a.rtmp.youtube.com/live2/YOUTUBE_STREAM_KEY
```

Add `YOUTUBE_STREAM_KEY` to your `.env` and update the deploy function to substitute it.

## Tech Stack

- **SRS 5** — RTMP ingest server (Docker)
- **ffmpeg** — Stream forwarding (Docker, one container per platform)
- **Stunnel** — TLS wrapper for Kick's RTMPS requirement
- **Bash** — CLI management scripts
- **Twitch Helix API** / **Kick Public API** — Stream metadata

## Cost

| Solution | Monthly |
|----------|---------|
| Restream Standard | $16 |
| Restream Professional | $39 |
| **This** | **~$5.59** |

Any VPS with Docker works. Hetzner is cheap and has 20TB/month bandwidth included. Even streaming 8 hours/day to 3 platforms uses ~5TB.

## License

MIT
