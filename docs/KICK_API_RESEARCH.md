# Kick.com API Research: Updating Stream Title & Category

**Date:** February 22, 2026

## 1. Official Public API -- YES, It Exists Now

Kick has a fully documented public API. This is relatively recent (launched mid-2025, iterating since).

- **Docs:** https://docs.kick.com
- **Developer Portal:** https://dev.kick.com
- **GitHub (community-contributed docs):** https://github.com/KickEngineering/KickDevDocs

## 2. The PATCH Channels Endpoint (Official)

**Endpoint:** `PATCH https://api.kick.com/public/v1/channels`

**Required OAuth Scope:** `channel:write`

**Auth Type:** User Access Token (OAuth 2.1 Authorization Grant Flow)

**Request Body (JSON):**
```json
{
  "stream_title": "New Stream Title",
  "category_id": 123,
  "custom_tags": ["tag1", "tag2"]
}
```

**Field Details:**
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `stream_title` | string | No* | Min length 1 |
| `category_id` | integer | No* | Min value 1 |
| `custom_tags` | string[] | No* | Max 10 items |

*At least one field must be set in the request.

**Response:** `204 No Content` on success.

**Error Codes:** 400 (Bad Request), 401 (Unauthorized), 403 (Forbidden), 500 (Internal Server Error)

**Known Bug (July 2025):** Changes via PATCH are reflected on the live stream immediately, but the GET channels endpoint may return stale/cached data for some time after patching. Issue tracked at: https://github.com/KickEngineering/KickDevDocs/issues/205

## 3. OAuth 2.1 Setup

**OAuth Server:** `https://id.kick.com`

**Endpoints:**
| Purpose | Method | URL |
|---------|--------|-----|
| Authorization | GET | `https://id.kick.com/oauth/authorize` |
| Token Exchange | POST | `https://id.kick.com/oauth/token` |
| Token Refresh | POST | `https://id.kick.com/oauth/token` |
| Token Revoke | POST | `https://id.kick.com/oauth/revoke` |
| Token Introspect | POST | `https://id.kick.com/oauth/token/introspect` |

**Flow:** OAuth 2.1 Authorization Grant with PKCE (S256)

**Required Parameters for Authorization:**
- `client_id` -- from your registered app
- `client_secret` -- from your registered app
- `response_type=code`
- `redirect_uri` -- must match app config
- `code_challenge` -- PKCE S256 challenge
- `code_challenge_method=S256`
- `state` -- CSRF protection
- `scope` -- space-separated list (e.g., `channel:write channel:read`)

**Available Scopes:**
| Scope | Description |
|-------|-------------|
| `user:read` | Read user info |
| `channel:read` | Read channel info |
| `channel:write` | Update livestream metadata (title, category, tags) |
| `chat:write` | Send chat messages |
| `streamkey:read` | Read stream key |
| `events:subscribe` | Subscribe to webhook events |

## 4. Getting Category IDs

To set a category, you need the numeric `category_id`. The API provides:

- `GET https://api.kick.com/public/v1/categories` -- Search/list categories
- `GET https://api.kick.com/public/v1/categories/{category_id}` -- Get category by ID

Docs: https://docs.kick.com/apis/categories

## 5. App Registration

1. Enable 2FA on your Kick account
2. Go to Account Settings > Developer tab
3. Create an app at dev.kick.com
4. Get your `client_id` and `client_secret`
5. Set your redirect URI

## 6. Third-Party Tools That Use This

### Streamer.bot
- Has native Kick integration via the official API
- `KickSetTitle(string title)` -- sets channel title
- `KickSetCategory(string categoryName)` -- sets category by name (resolves ID internally)
- Uses the official Kick public API under the hood

### KickLib (C#)
- NuGet package: `KickLib 1.8.0`
- Supports both official and unofficial endpoints
- GitHub: https://github.com/Bukk94/KickLib

### kick-sdk (Go)
- `UpdateStream(ctx, UpdateStreamInput{CategoryID, StreamTitle})`
- Uses `channel:write` scope
- GitHub: https://github.com/glichtv/kick-sdk

### kick.py (Python)
- Community Python wrapper
- GitHub: https://github.com/cibere/kick.py

### KickApi (Python)
- Another Python option on PyPI
- https://pypi.org/project/KickApi/

## 7. Unofficial/Legacy Endpoints (Pre-Public API)

These were reverse-engineered from the Kick website and may still work but are NOT recommended:

| Method | Endpoint | Notes |
|--------|----------|-------|
| POST | `stream/update` | Old stream update |
| POST | `stream/{liveStream}/update` | Old per-stream update |
| PUT | `stream/info` | Old stream info update |
| PUT | `channels` | Old channel update |
| POST | `api/v2/stream/update` | V2 variant |

**Auth for unofficial endpoints:** Cookie-based (session auth from browser login), not OAuth.

Documented by community: https://github.com/fb-sean/kick-website-endpoints

## 8. Alternative Approaches (If API Isn't Enough)

### Browser Automation (Puppeteer/Playwright)
- Log into Kick via browser automation
- Navigate to stream settings
- Fill in title/category fields and save
- Works but fragile, breaks on UI changes

### Session Cookie Hijack
- Extract session cookies from an authenticated browser
- Use them to call the unofficial internal API endpoints
- Fragile, cookies expire, breaks on auth changes

### Streamer.bot as Middleware
- If Multistreamer just needs to trigger title/category changes, could use Streamer.bot's WebSocket server as an intermediary
- Send commands to Streamer.bot, which handles the Kick API auth

## 9. Recommended Approach for Multistreamer

Use the **official public API** (`PATCH https://api.kick.com/public/v1/channels`):

1. Register an app at dev.kick.com
2. Implement OAuth 2.1 PKCE flow to get a user access token with `channel:write` scope
3. Store and refresh tokens
4. Call `PATCH /public/v1/channels` with `stream_title` and/or `category_id`
5. Use `GET /public/v1/categories` to search for category IDs by name

This is stable, documented, and what all the major tools (Streamer.bot, etc.) now use.

## Sources

- Official Kick API Docs: https://docs.kick.com
- Kick Developer Portal: https://dev.kick.com
- KickDevDocs GitHub: https://github.com/KickEngineering/KickDevDocs
- Channel PATCH bug report: https://github.com/KickEngineering/KickDevDocs/issues/205
- Unofficial endpoints list: https://github.com/fb-sean/kick-website-endpoints
- Go SDK: https://pkg.go.dev/github.com/glichtv/kick-sdk
- Streamer.bot Kick title docs: https://docs.streamer.bot/api/sub-actions/kick/channel/set-channel-title/
- Streamer.bot Kick category docs: https://docs.streamer.bot/api/sub-actions/kick/channel/set-channel-category
- OAuth flow docs: https://github.com/KickEngineering/KickDevDocs/blob/main/getting-started/generating-tokens-oauth2-flow.md
