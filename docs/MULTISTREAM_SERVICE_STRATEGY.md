# Multistream Service Strategy

**Created:** February 20, 2026
**Status:** Infrastructure built, personal use first, then decide on productization

---

## The Opportunity

Restream charges $16-39/month for something that costs ~$5/month to self-host. The technology is open source (SRS), the infrastructure is commodity (Hetzner), and streamers are getting gouged.

**Restream's pricing:**
- Standard: $16/month (3 platforms)
- Professional: $39/month (5 platforms, 1080p)
- Business: $199/month (8 platforms)

**Our cost:**
- Hetzner CX22: €4.99/month (~$5.59 with IPv4)
- Hetzner Dedicated (50+ users): €99/month
- Cost per user at scale: ~€1-2/month
- **Margin: 80-90%**

---

## Three Strategic Options

### Option 1: Open Source / Tutorial Play

**What:** Publish the setup guide, give away the config files, make a YouTube video.

**Brand value:**
- "BroTeam teaches you how to stop paying Restream $400/year"
- Anti-corporate, DIY energy
- Builds credibility with streamer audience
- Content piece for channel revival

**Revenue:** Zero direct, but drives audience to other monetized products (Cartridge, merch, etc.)

**Effort:** Low — already built, just need to document and publish

**Risks:**
- Tech support DMs (mitigate: "no support, figure it out")
- None really, it's goodwill

---

### Option 2: Hosted Service (Restream Competitor)

**What:** Run the infrastructure, charge monthly subscription.

**Pricing strategy (undercut Restream by 50%):**

| Tier | Price | Platforms | Features |
|------|-------|-----------|----------|
| Free | $0 | 2 | Watermark, shared resources |
| Starter | $8/month | 5 | No watermark, basic analytics |
| Pro | $15/month | Unlimited | Priority support, advanced analytics |
| Team | $30/month | Unlimited | Multiple users, API access |

**Revenue potential:**
- 100 users × $10 avg = $1,000/month
- 500 users × $10 avg = $5,000/month
- 1,000 users × $10 avg = $10,000/month

**Infrastructure scaling:**
- 1-20 users: Single Hetzner CX22 ($5.59/month)
- 20-100 users: Hetzner Dedicated EX101 (€99/month)
- 100+ users: Multiple dedicated servers, load balancing

**Effort:** Medium-high
- Web dashboard for user management
- Stripe billing integration
- Per-user stream key isolation
- Monitoring and alerting
- Support system

**Risks:**
- Uptime responsibility (streamers will be pissed if you go down mid-stream)
- Competition from Restream (they have resources)
- Support burden

---

### Option 3: Hybrid Model (Recommended)

**What:** Open source the self-hosted version, offer paid hosting for non-technical users.

**The playbook:**
1. **Free tier:** Full config files on GitHub, tutorial video, "do it yourself"
2. **Paid tier:** "Don't want to deal with servers? We host it for $8/month"

**Why this works:**
- Technical users weren't going to pay anyway — let them self-host, they become evangelists
- Non-technical users pay you instead of Restream — 50% cheaper, they're happy
- Open source version is marketing for the paid version
- Same model as: Ghost, Plausible, Fathom, Bitwarden, GitLab

**Revenue potential:** Same as Option 2, but with better marketing engine (the free users spread the word)

**Effort:** Same as Option 2 for the paid tier, minimal for the free tier

---

## Brand Options

### Under Cartridge Umbrella
- **Cartridge Stream** or **Cartridge Relay**
- Fits the gaming/streaming empire
- Cross-sell to GameStocks/Cartridge Intelligence users
- "The streaming infrastructure for indie creators"

### Standalone Brand
- **StreamForge**
- **Multicast**
- **Relay.gg**
- **OpenStream**
- More generic, wider appeal beyond gaming

### BroTeam Adjacent
- **BroStream** (lol)
- Leverages existing audience
- But ties it to personal brand (limits growth?)

**Recommendation:** Start under Cartridge, spin out if it takes off.

---

## Technical Architecture (Production)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Load Balancer                               │
│                    (Hetzner Load Balancer €5/mo)                    │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
┌───────────────┐           ┌───────────────┐           ┌───────────────┐
│  SRS Node 1   │           │  SRS Node 2   │           │  SRS Node N   │
│  (Users 1-50) │           │  (Users 51-100)│          │  (Overflow)   │
└───────────────┘           └───────────────┘           └───────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        Web Dashboard                                │
│                    (Railway - existing infra)                       │
│  • User auth (OAuth with Twitch/Google)                            │
│  • Stream key management                                            │
│  • Platform connections (Twitch, Kick, YouTube API)                │
│  • Analytics dashboard                                              │
│  • Billing (Stripe)                                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         Database                                    │
│                    (Railway PostgreSQL)                             │
│  • Users, subscriptions, stream configs                            │
│  • Analytics data, usage metrics                                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Feature Roadmap

### Phase 1: Personal Use (NOW)
- [x] SRS config files created
- [x] Hetzner server provisioned
- [ ] Deploy SRS to Hetzner
- [ ] Test with personal stream keys
- [ ] Stream to Twitch + Kick + YouTube simultaneously

### Phase 2: Polish & Document
- [ ] Refine config based on personal testing
- [ ] Write comprehensive setup guide
- [ ] Record tutorial video
- [ ] Publish to GitHub

### Phase 3: Hosted MVP (If pursuing)
- [ ] Web dashboard (user signup, stream key management)
- [ ] Stripe billing integration
- [ ] Per-user SRS container orchestration
- [ ] Basic analytics (stream duration, platforms, bandwidth)

### Phase 4: Growth Features
- [ ] Unified chat aggregation (Twitch + Kick + YouTube in one view)
- [ ] AI clip generation (auto-highlight detection)
- [ ] Stream health monitoring and alerts
- [ ] Custom RTMP endpoints (for advanced users)
- [ ] Team accounts

### Phase 5: Cartridge Integration
- [ ] Bundle with Cartridge Intelligence subscription
- [ ] GameStocks overlay integration
- [ ] Audience sentiment dashboard (tie into neural engagement later?)

---

## Competitive Analysis

| Feature | Restream | StreamYard | Ours (Planned) |
|---------|----------|------------|----------------|
| Price | $16-199/mo | $25-75/mo | $0-15/mo |
| Self-host option | No | No | Yes (free) |
| Platforms | 30+ | 8+ | Unlimited (RTMP) |
| Unified chat | Yes | Yes | Phase 4 |
| Recording | Yes | Yes | Via platforms |
| Analytics | Basic | Basic | Phase 3 |
| Open source | No | No | **Yes** |

**Our differentiators:**
1. **Price** — 50%+ cheaper than Restream
2. **Open source** — Self-host option, no lock-in
3. **Gaming native** — Built by streamers for streamers
4. **No corporate bullshit** — BroTeam energy

---

## Marketing Angles

### Tutorial/Content Play
- "How I Replaced Restream for $5/Month"
- "Stop Paying Restream $400/Year"
- "The Open Source Multistreaming Setup Every Streamer Needs"
- Reddit posts in r/Twitch, r/streaming, r/obs
- YouTube tutorial with personality

### Service Launch
- "Multistreaming without the markup"
- "Built by streamers, priced fairly"
- "Self-host free, or let us handle it for $8"
- BroTeam audience as initial user base
- Dave Oshry / New Blood signal boost?

---

## Revenue Projections

### Conservative (100 paid users by EOY 2026)
- 100 × $10/month = $1,000/month
- Infrastructure: ~$100/month (Hetzner dedicated)
- Net: $900/month / $10,800/year

### Moderate (500 paid users by EOY 2027)
- 500 × $10/month = $5,000/month
- Infrastructure: ~$300/month
- Net: $4,700/month / $56,400/year

### Aggressive (2,000 paid users by EOY 2028)
- 2,000 × $10/month = $20,000/month
- Infrastructure: ~$1,000/month
- Net: $19,000/month / $228,000/year

---

## SR&ED Potential

If building novel features, eligible for 35% tax credit:
- Unified chat aggregation with sentiment analysis
- AI-powered stream health prediction
- Automatic clip detection using engagement signals
- EEG integration for neural engagement measurement (tie to Brain Interface project)

Document development hours starting now.

---

## Next Steps

1. **TODAY:** Deploy SRS to Hetzner, test personal streaming
2. **THIS WEEK:** Stream to Twitch + Kick + YouTube, verify stability
3. **NEXT WEEK:** Document setup process, consider tutorial video
4. **DECISION POINT:** After personal use proves stable, decide: tutorial only, or build the service?

---

## Connection to Empire

```
                    ┌─────────────────────┐
                    │     CARTRIDGE       │
                    │   (Umbrella Brand)  │
                    └──────────┬──────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
       ▼                       ▼                       ▼
┌─────────────┐        ┌─────────────┐        ┌─────────────┐
│  Backlogger │        │  GameStocks │        │  Cartridge  │
│ (Consumer)  │        │ (Sentiment) │        │ Intelligence│
└─────────────┘        └─────────────┘        └──────┬──────┘
                                                     │
                               ┌─────────────────────┼─────────────────────┐
                               │                     │                     │
                               ▼                     ▼                     ▼
                       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
                       │  Cartridge  │       │   Scripter  │       │    Brain    │
                       │   Stream    │       │  (Audience  │       │  Interface  │
                       │ (Multistream│       │   Testing)  │       │   (EEG)     │
                       └─────────────┘       └─────────────┘       └─────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   BroTeam/      │
                    │   Streaming     │
                    │   Revival       │
                    └─────────────────┘
```

**Cartridge Stream** feeds into:
- BroTeam streaming infrastructure (personal use)
- Cartridge Intelligence bundle (indie streamers covering games)
- Cross-promotion with GameStocks users
- Future: Neural engagement overlay (EEG + stream = real-time audience brain state)

---

## Summary

**What we built today:** Self-hosted Restream alternative for ~$5.59/month

**What it could become:**
- Tutorial/content piece (free, builds credibility)
- Hosted service ($8-15/month, undercuts Restream by 50%)
- Cartridge ecosystem product (bundled with intelligence suite)

**The play:** Start with personal use, prove it works, then decide how public to go with it.

---

*"We're building an empire here."*
