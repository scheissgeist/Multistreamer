# Multistreamer

**Status:** ✅ Live and operational
**Server:** Hetzner Cloud (5.78.187.172)
**Cost:** $5.59/month (vs Restream's $16-39/month)

Stream to Twitch, Kick, and YouTube simultaneously from a single OBS upload.

---

## Quick Start

### Using the Server

**In OBS:**
```
Service: Custom
Server: rtmp://5.78.187.172/live
Stream Key: livestream
```

Hit "Start Streaming" — you're now live on Twitch + Kick simultaneously!

---

## Server Details

| Property | Value |
|----------|-------|
| Provider | Hetzner Cloud |
| Location | Hillsboro, OR (us-west) |
| IP | 5.78.187.172 |
| Type | CPX11 (2 vCPU, 4GB RAM, 40GB SSD) |
| Bandwidth | 20 TB/month included |
| Monthly Cost | $5.59 USD |

### Current Platforms

- ✅ **Twitch** - Active
- ✅ **Kick** - Active (via Stunnel/RTMPS)
- ⏸️ **YouTube** - Ready to add

---

## SSH Access

```bash
ssh root@5.78.187.172
```

SSH key: `C:\Users\seanw\.ssh\id_ed25519`

### Common Commands

```bash
# View SRS logs
docker logs -f multistream-srs

# Restart after config changes
cd /opt/multistream && docker compose restart

# Check status
docker ps && systemctl status stunnel4

# Edit stream keys
nano /opt/multistream/conf/srs.conf
```

### Web Console

http://5.78.187.172:8080 → Click "SRS console"

---

## Adding YouTube

1. Get stream key: https://studio.youtube.com → Create → Go Live → Stream
2. SSH to server: `ssh root@5.78.187.172`
3. Edit config: `nano /opt/multistream/conf/srs.conf`
4. Uncomment YouTube line and add your key
5. Restart: `cd /opt/multistream && docker compose restart`

---

## Project Files

```
E:\Multistreamer\
├── docs\
│   ├── MULTISTREAM_DEPLOYMENT_LOG.md    # Full deployment details
│   ├── MULTISTREAM_SERVICE_STRATEGY.md  # Business strategy & roadmap
│   └── cheapest-multistream-options-*.md # Research notes
├── config\
│   └── (server config files to be added)
└── scripts\
    └── (deployment/management scripts to be added)
```

---

## Cost Comparison

| Solution | Monthly | Annual | Savings |
|----------|---------|--------|---------|
| Restream Standard | $16 | $192 | - |
| Restream Pro | $39 | $468 | - |
| **This Setup** | **$5.59** | **$67** | **$125-401/year** |

---

## Next Steps

### Personal Use
- [x] Server deployed and working
- [x] Twitch + Kick configured
- [ ] Add YouTube stream key
- [ ] Test stability over 1-2 weeks

### Potential Service ("Cartridge Stream")
- [ ] Document setup process
- [ ] Create tutorial video
- [ ] Decide: Open source tutorial or hosted service?
- [ ] If service: Web dashboard, Stripe billing, user isolation

See [docs/MULTISTREAM_SERVICE_STRATEGY.md](docs/MULTISTREAM_SERVICE_STRATEGY.md) for full roadmap.

---

## Tech Stack

- **SRS 5** (Docker) - RTMP ingest and forwarding
- **Stunnel** - TLS wrapper for Kick's RTMPS requirement
- **UFW** - Firewall
- **Hetzner Cloud** - Infrastructure

---

## Maintenance

Server is self-maintaining. Only need to:
- Update stream keys when they change
- Monitor bandwidth (currently using <5% of 20TB limit)
- Pull SRS updates occasionally

---

**Built:** February 20, 2026
**Last Updated:** February 22, 2026
