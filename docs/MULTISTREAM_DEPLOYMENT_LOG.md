# Multistream Server Deployment Log

**Date:** February 20, 2026
**Status:** LIVE AND OPERATIONAL

---

## What We Built

A self-hosted Restream alternative running on Hetzner Cloud. Single upload from OBS, automatic forwarding to Twitch, Kick, and YouTube simultaneously.

**Cost:** $5.59/month (vs Restream's $16-39/month)
**Savings:** $125-400/year

---

## Infrastructure

### Server Details

| Property | Value |
|----------|-------|
| Provider | Hetzner Cloud |
| Server Name | Restreamer |
| Location | Hillsboro, OR (us-west) |
| IP Address | 5.78.187.172 |
| Type | CPX11 (Regular Performance) |
| Specs | 2 vCPU, 4GB RAM, 40GB SSD |
| Bandwidth | 20 TB/month included |
| Monthly Cost | €4.99 + €0.60 IPv4 = ~$5.59 |

### Software Stack

| Component | Purpose |
|-----------|---------|
| **SRS 5** (Docker) | RTMP ingest and forwarding |
| **Stunnel** | TLS wrapper for Kick's RTMPS requirement |
| **UFW** | Firewall (ports 22, 1935, 8080, 1985) |

### Architecture

```
┌─────────┐     RTMP (6 Mbps)      ┌──────────────────────────────┐
│   OBS   │ ────────────────────▶ │  Hetzner: 5.78.187.172       │
└─────────┘                       │                              │
                                  │  ┌─────────────────────────┐ │
                                  │  │ SRS (Docker :1935)      │ │
                                  │  │ - Receives RTMP stream  │ │
                                  │  │ - Forwards to platforms │ │
                                  │  └───────────┬─────────────┘ │
                                  │              │               │
                                  │   ┌──────────┼──────────┐    │
                                  │   │          │          │    │
                                  │   ▼          ▼          ▼    │
                                  │ Twitch    Stunnel   YouTube  │
                                  │ (RTMP)    (:1936)   (RTMP)   │
                                  │             │                │
                                  └─────────────┼────────────────┘
                                                │
                                                ▼
                                              Kick
                                            (RTMPS)
```

---

## Current Configuration

### Platforms Configured

| Platform | Status | Protocol | Notes |
|----------|--------|----------|-------|
| **Twitch** | ✅ Active | RTMP | Direct forward |
| **Kick** | ✅ Active | RTMPS (via Stunnel) | Requires TLS wrapper |
| **YouTube** | ⏸️ Pending | RTMP | Add key when ready |

### OBS Settings

```
Service: Custom
Server: rtmp://5.78.187.172/live
Stream Key: livestream (or any name)
```

### File Locations on Server

```
/opt/multistream/
├── docker-compose.yml
├── conf/
│   └── srs.conf          # Main config with stream keys
└── logs/

/etc/stunnel/
└── kick.conf             # Stunnel TLS config for Kick
```

---

## SSH Access

```powershell
# Connect to server
ssh root@5.78.187.172

# View SRS logs
docker logs -f multistream-srs

# Restart SRS after config changes
cd /opt/multistream && docker compose restart

# View stunnel status
systemctl status stunnel4

# Edit stream keys
nano /opt/multistream/conf/srs.conf
```

SSH key location: `C:\Users\seanw\.ssh\id_ed25519`

---

## Bandwidth & Cost Analysis

### Monthly Cost Breakdown

| Item | Cost |
|------|------|
| CX22 Server | €4.99 |
| IPv4 Address | €0.60 |
| **Total** | **€5.59 (~$5.59 USD)** |
| Bandwidth overage | €1/TB (if >20 TB) |

### Bandwidth Usage Estimates

| Scenario | Monthly Usage | % of 20 TB Limit |
|----------|---------------|------------------|
| 4 hrs/day × 6 Mbps × 2 platforms | ~970 GB | 4.8% |
| 4 hrs/day × 6 Mbps × 3 platforms | ~1.5 TB | 7.5% |
| 8 hrs/day × 8 Mbps × 3 platforms | ~5.2 TB | 26% |

**Conclusion:** Even heavy streaming won't approach the 20 TB limit.

### Cost Comparison

| Solution | Monthly | Annual |
|----------|---------|--------|
| Restream Standard | $16 | $192 |
| Restream Professional | $39 | $468 |
| **This setup** | **$5.59** | **$67** |
| **Savings vs Restream Standard** | **$10.41** | **$125** |
| **Savings vs Restream Pro** | **$33.41** | **$401** |

---

## Maintenance Commands

### Restart Everything
```bash
ssh root@5.78.187.172 "cd /opt/multistream && docker compose restart && systemctl restart stunnel4"
```

### Update Stream Keys
```bash
ssh root@5.78.187.172 "nano /opt/multistream/conf/srs.conf"
# Edit keys, then:
ssh root@5.78.187.172 "cd /opt/multistream && docker compose restart"
```

### Check Server Status
```bash
ssh root@5.78.187.172 "docker ps && systemctl status stunnel4"
```

### View Active Streams
Open: http://5.78.187.172:8080 → Click "SRS console"

### Pull SRS Updates
```bash
ssh root@5.78.187.172 "cd /opt/multistream && docker compose pull && docker compose up -d"
```

---

## Adding YouTube Later

1. Get stream key from https://studio.youtube.com → Create → Go Live → Stream
2. SSH into server and edit config:
   ```bash
   ssh root@5.78.187.172 "nano /opt/multistream/conf/srs.conf"
   ```
3. Uncomment the YouTube line and add your key:
   ```
   destination     rtmp://a.rtmp.youtube.com/live2/YOUR_KEY_HERE;
   ```
4. Restart:
   ```bash
   ssh root@5.78.187.172 "cd /opt/multistream && docker compose restart"
   ```

---

## Troubleshooting

### Stream not reaching platform
1. Check SRS logs: `docker logs multistream-srs`
2. Verify stream key is correct (no extra spaces)
3. For Kick: Check stunnel is running: `systemctl status stunnel4`

### Can't connect to server
1. Verify server is running in Hetzner console
2. Check firewall: `ssh root@5.78.187.172 "ufw status"`
3. Verify ports are open: 1935 (RTMP), 8080 (web), 1985 (API)

### High latency between platforms
- Normal: 2-5 second variance between Twitch/Kick/YouTube
- Each platform has its own ingest processing time

---

## Security Notes

⚠️ **Stream keys are stored in plain text** on the server at `/opt/multistream/conf/srs.conf`

The server is protected by:
- SSH key authentication (no password login)
- UFW firewall (only necessary ports open)
- Root-only access

For production multi-user service, would need:
- Environment variables or secrets manager
- Per-user isolation
- RTMP authentication

---

## Next Steps (If Productizing)

See: [MULTISTREAM_SERVICE_STRATEGY.md](MULTISTREAM_SERVICE_STRATEGY.md)

1. Test personal streaming stability over 1-2 weeks
2. Document setup process for tutorial video
3. Decide: Open source tutorial only, or hosted service?
4. If service: Build web dashboard, Stripe billing, user isolation

---

## Session Summary

**What happened:**
1. Researched Kick partnership opportunity and multistreaming options
2. Discovered OBS plugin (free) and self-hosted SRS (better for service)
3. Compared Railway/Fly.io (expensive bandwidth) vs Hetzner (20TB included)
4. Created Hetzner Cloud account and provisioned server
5. Generated SSH key, deployed Docker + SRS
6. Configured Stunnel for Kick's RTMPS requirement
7. Added Twitch and Kick stream keys
8. Documented everything for future reference and potential productization

**Total time:** ~45 minutes from idea to working multistream server

**Empire expansion:** This fits into the Cartridge ecosystem as "Cartridge Stream" — potential revenue stream, content piece, or both.

---

*"We're building an empire here."*
