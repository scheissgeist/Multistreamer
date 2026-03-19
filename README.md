# Multistreamer

Self-hosted multistreaming to any RTMP/RTMPS destination from a single OBS output. Twitch and Kick are built in. Add YouTube, Facebook, X, or any platform that accepts RTMP — each one is just another ffmpeg container.

~$5/month on a VPS. No platform limits, no watermarks, no third-party middleman watching your stream.

## How It Works

```
                        → ffmpeg → Twitch (RTMP)
OBS → Your Server (SRS) → ffmpeg → Stunnel → Kick (RTMPS)
                        → ffmpeg → YouTube (RTMP)
                        → ffmpeg → anything that accepts RTMP
```

OBS sends one RTMP stream to your server. SRS receives it. Each platform gets its own ffmpeg container that pulls from SRS and pushes to that platform's ingest. No re-encoding — just copies the stream (`-c copy`), so one cheap VPS can handle many destinations.

Platforms that require TLS (like Kick) go through Stunnel on the server.

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

## Adding More Platforms

Any platform that accepts RTMP or RTMPS can be added. Each one is just another ffmpeg service in `docker-compose.yml`.

### RTMP platforms (YouTube, Facebook, X, etc.)

Add a service block like this:

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
      rtmp://a.rtmp.youtube.com/live2/YOUR_STREAM_KEY
```

Then add the stream key to `.env`, add a `sed` substitution in the deploy function, and redeploy.

Common RTMP ingest URLs:

| Platform | Ingest URL |
|----------|-----------|
| YouTube | `rtmp://a.rtmp.youtube.com/live2/` |
| Facebook | `rtmps://live-api-s.facebook.com:443/rtmp/` |
| X (Twitter) | `rtmp://or.contribute.live-video.net/rtmp/` |
| Instagram | Via Facebook Live (same ingest) |
| Rumble | `rtmp://live-east.rumble.com/live/` |

### RTMPS platforms (TLS required)

Some platforms require RTMPS (RTMP over TLS). For these, add a Stunnel config like the one included for Kick:

1. Create a stunnel config in `config/` pointing to the platform's ingest host on port 443
2. Set `accept` to a unique local port (e.g., 1937)
3. Point the ffmpeg container at `rtmp://127.0.0.1:1937/app/YOUR_KEY`

Facebook uses RTMPS by default — you'd need a Stunnel entry for it too.

### How many platforms can one server handle?

ffmpeg with `-c copy` (no re-encoding) uses almost no CPU. Each destination just copies the stream bytes to another socket. A $5 VPS can comfortably handle 5-10 destinations. Bandwidth is the real limit — at 6 Mbps per destination, 5 platforms = 30 Mbps = ~10 TB/month.

## Tech Stack

- **SRS 5** — RTMP ingest server (Docker)
- **ffmpeg** — Stream forwarding (Docker, one container per platform)
- **Stunnel** — TLS wrapper for Kick's RTMPS requirement
- **Bash** — CLI management scripts
- **Twitch Helix API** / **Kick Public API** — Stream metadata

## Why Not Restream?

Restream's free tier gives you 2 destinations, which is fine if that's all you need. But:

- Their paid plans ($16-39/month) kick in fast once you want more platforms, 1080p, or no watermark
- Your stream routes through their servers — they can see it, throttle it, or go down mid-stream
- They control which platforms you can use

This gives you unlimited destinations for a flat ~$5/month VPS cost, full control, and no middleman. The tradeoff is you set it up yourself.

## License

MIT
