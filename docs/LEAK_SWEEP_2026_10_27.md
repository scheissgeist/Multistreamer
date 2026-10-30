# Leak sweep — 2026-10-27

Sweep of this **public** repo for secrets, copyrighted material and personal
info, across the current tree and full git history on every branch.
Secret values are never reproduced here; at most the first 4 characters are shown.

## TL;DR

1. **A Twitch stream key and a Kick stream key are in public git history**
   (commit `0d1c4dd`, file `.env.example`). They were deleted from the tree in
   `9683c57`, but every branch still contains that commit. **Rotate both keys
   now.** Deleting them from the file did not un-publish them.
2. **Anyone can publish video through the relay.** SRS accepts RTMP publishes
   on port 1935 with no auth. The stream name (`livestream`) is printed in the
   README, and the ffmpeg containers forward whatever arrives on it to Twitch
   and Kick. That lets anyone broadcast on Sean's channels without needing his
   platform keys.
3. **The SRS HTTP API (port 1985) is open to the internet with no auth.** It
   shows connected client IPs (Sean's home IP while live) and active stream
   names, and it can disconnect the publisher.
4. The server IP, root SSH login and a Windows username are in history (and
   in one commit message), but not in HEAD.

No copyrighted material found. No binary files have ever been committed.

## What was scanned

| Item | Detail |
|---|---|
| Refs | `origin/main` (`40ad6c5`), `origin/public` (`7f70f8b`), `origin/claude/serene-hamilton-c2fbon`. No tags exist. 9 commits, 87 objects total. |
| "HEAD" in the table below | Tip of `main` (`40ad6c5`) **and** tip of `public` (`7f70f8b`). Both were checked; they agree for every finding. |
| gitleaks 8.21.2 | `gitleaks git --log-opts="--all" --redact` (9 commits scanned) and `gitleaks dir` on the working tree. Default ruleset. **0 findings.** |
| trufflehog 3.88.0 | `trufflehog git file://. --no-update` (all refs, 99 chunks). **0 findings.** |
| Custom regex pass | `git log -p --all --full-history` piped through a Python scanner. Needed because neither tool has rules for stream-key formats. Patterns: Twitch `live_\d+_…`, Kick `sk_[a-z]{2}-[a-z]+-\d_…`, YouTube `xxxx-xxxx-xxxx-xxxx(-xxxx)`, `rtmps?://…` (key path segment checked), `(stream_?key|api_?key|secret|token|passw(or)?d|pwd|auth|client_id|bearer)\s*[:=]…`, IPv4, email, phone, US street address, `-----BEGIN … PRIVATE KEY`, `ssh-rsa/ssh-ed25519/root@/id_rsa/.pem`, hex ≥32, base64-ish ≥30, dynamic-DNS/Hetzner hostnames. |
| Personal-info pass | `git grep` over every revision for the owner's name and username variants, `C:\Users\`, `/home/<user>`, `/Users/<user>`, the server IP prefix; commit messages and author/committer fields via `git log --all --format=%B/%ae/%ce`. |
| Filename pass | Every path ever committed (`git log --all --name-status`) checked for `.env`, `*.pem`, `*.key`, `credentials*`, `id_*`, `*.p12`. Only `.env.example` matched, and it is a template. |
| Copyright pass | Every blob ever committed listed by size and type. Each blob checked for NUL bytes (binary). Grepped for fonts/media/SDK files. Largest blob: `web/templates/dashboard.html`, 28 KB. All blobs are text. |
| Relay auth | `config/srs.conf`, `config/docker-compose.yml`, `scripts/setup-server.sh` (public branch), `scripts/multistream.sh`, `web/server.py`. The relay uses **SRS 5**, not nginx-rtmp, so the "publish" check was done against SRS. |

Nothing was connected to: no live server, no platform APIs, and no key validity checks.

## Findings

### Secrets

| # | Where | Type | In HEAD? | Action |
|---|---|---|---|---|
| S1 | `0d1c4dd` `.env.example` line 4 (removed in `9683c57`) | Twitch stream key (`live…`, 46 chars) | n | **Rotate key** (reset it in the Twitch creator dashboard's stream settings). History purge optional: the key has been public since 2026-02-25, so rotation is the fix. |
| S2 | `0d1c4dd` `.env.example` line 5 (removed in `9683c57`) | Kick stream key (`sk_u…`, 49 chars, Kick format) | n | **Rotate key** (reset it in Kick's creator dashboard stream settings). History purge optional, same reason. |
| S3 | `README.md`, `docker-compose.yml`, `dashboard.html`, `docs/SETUP_GUIDE.md` (public branch) | Relay ingest stream name `livestream`. This is the de facto publish password (see A1). | y | Fixed in this PR: now `INGEST_STREAM_KEY` from `.env`. **Sean must set it** to a random value, redeploy, and update OBS. |

Every other `rtmp://`, `*_KEY=`, `client_secret=` and `token=` hit across history
is a placeholder (`TWITCH_STREAM_KEY`, `YOUR_KEY_HERE`, …) or a `$VAR` / `${VAR}`
lookup. No OAuth client secrets, access/refresh tokens, passwords, SSH keys or
`.env` files were ever committed.

### Personal info / infrastructure

| # | Where | Type | In HEAD? | Action |
|---|---|---|---|---|
| P1 | `e5d7294` commit **message** ("Hetzner Cloud server (5.78…)") | Server IP | n (commit message, permanent) | History purge needed to remove (message rewrite). Otherwise treat the IP as public; see recommendations. |
| P2 | `e5d7294` `README.md`, `docs/MULTISTREAM_DEPLOYMENT_LOG.md`; `0d1c4dd`/`d7de755` `README.md`, `.env.example` (all removed in `9683c57`) | Server IP (`5.78…`) next to `ssh root@…`, open ports 8080/1985, and the server's file layout (`/opt/multistream/conf/srs.conf` "with stream keys") | n | History purge optional. More useful: keep root SSH key-only (the log says it is), and close 1985/8080 (A2/A3). |
| P3 | `e5d7294`/`d7de755` `README.md`, `docs/MULTISTREAM_DEPLOYMENT_LOG.md` line 119 | Local Windows username in SSH key path (`C:\Users\sean…\.ssh\id_ed25519`). Path only, no key material. | n | Low. History purge only if desired. |
| P4 | `e5d7294` `docs/MULTISTREAM_DEPLOYMENT_LOG.md` | Server location (Hetzner Hillsboro, OR), server name, plan | n | Low. No action. |
| P5 | `e5d7294` `docs/cheapest-multistream-options-69424b28.md` | ChatGPT conversation ID and a personal note/tag from a ChatGPT export | n | Low. History purge only if desired. |
| P6 | `config/docker-compose.yml` on `main` | `TZ=America/Vancouver` (rough location) | y (main) / n (public, already `UTC`) | Fixed in this PR (`TZ=UTC`). |
| P7 | All commits: author/committer fields | Personal Gmail address (`sean…@gmail.com`) | n/a (commit metadata) | Normal for GitHub. To stop it in future commits, use the GitHub `noreply` address (`git config user.email`). Changing old commits requires a history rewrite. |

No phone numbers, home addresses or private-LAN IPs found. The only other IPs are
`127.0.0.1` and documentation placeholders (`203.0.113.42`, `123.45.67.89`).

### Copyrighted material

None. Every blob ever committed is text written for this project: shell, Python,
HTML/CSS, YAML, Markdown, plus the repo's own MIT `LICENSE`. There are no fonts
(the dashboard uses the system font stacks `Segoe UI` and `system-ui`), media, or
SDK dumps. `docs/KICK_API_RESEARCH.md` is a summary that links to Kick's public
docs, not a copy of them.

### Relay control, stats and publish auth

| # | Where | Issue | In HEAD? | Action |
|---|---|---|---|---|
| A1 | `config/srs.conf` (no `security` or `http_hooks` block), port 1935 opened by `scripts/setup-server.sh` | **RTMP publish is unauthenticated.** Anyone can publish to `rtmp://<server>/live/livestream`; `forward-twitch` and `forward-kick` pull that exact stream and push it to Sean's channels. | y | Partly fixed in this PR: ingest name now comes from `INGEST_STREAM_KEY`, and deploy warns while it is still the default. **Only effective once A2 is fixed too**, because the open API lists stream names. Stronger option: SRS `http_hooks { on_publish … }` that checks a token, or `security { deny publish all; allow publish <home IP>; }` if your home IP is stable. |
| A2 | `config/srs.conf` `http_api { listen 1985; }`, published in compose, opened in ufw by `setup-server.sh` | **SRS HTTP API is public and unauthenticated.** `GET /api/v1/clients/` shows client IPs (yours while live). `GET /api/v1/streams/` reveals the ingest stream name. `DELETE /api/v1/clients/<id>` kicks your publisher. | y | Not changed here: `multistream.sh status/streams/health` and the dashboard call it remotely. Options: (a) upgrade SRS to ≥5.0.152 and enable `http_api { auth { enabled on; username …; password …; } }` (it protects `/api/v1/` only); or (b) publish 1985 on `127.0.0.1` only and query it over SSH (`ssh root@$SERVER_IP curl -s localhost:1985/...`), then remove the ufw rule. |
| A3 | `config/srs.conf` `http_server { listen 8080; }` + HLS enabled; ufw opens 8080 | Public SRS console and HLS output of every stream on the server | y | If the HLS output isn't used, disable `hls` and stop publishing 8080. Otherwise firewall it. The console is only useful with the API, so it also needs A2. |
| A4 | `web/server.py` | Local dashboard: binds `127.0.0.1:3000`, has no auth, and runs SSH as root. Not internet-exposed. JSON endpoints need `Content-Type: application/json`, but `/api/deploy` and `/api/restart` take no body, so a malicious web page open in the same browser could trigger them (CSRF). | y | Low. Optional: require a header or token on POST routes. |

## Recommended actions for Sean (in order)

1. **Rotate the Twitch and Kick stream keys** (S1, S2). Put the new ones only in your local `.env` and redeploy.
2. **Close or authenticate port 1985** (A2), then set `INGEST_STREAM_KEY` to a random value (`openssl rand -hex 24`) in `.env`, put the same value in OBS as the stream key, and run `bash scripts/multistream.sh deploy` (A1).
3. Close 8080 if you don't use HLS (A3).
4. Port the `INGEST_STREAM_KEY` change to the `public` branch, or merge `main` into it. That branch still hard-codes `livestream` in `docker-compose.yml`, `README.md`, `docs/SETUP_GUIDE.md`, `dashboard.html` and the Rumble/X forwarders. Its `server.py` deploy also needs the same `INGEST_STREAM_KEY` replace line.
5. Optional history purge (your call; this sweep rewrote nothing). `git filter-repo` on all branches would remove `.env.example@0d1c4dd`, `docs/MULTISTREAM_DEPLOYMENT_LOG.md`, `docs/cheapest-multistream-options-69424b28.md` and the IP in commit `e5d7294`'s message. GitHub keeps old commits reachable by SHA, and any forks or clones keep them too, so a purge reduces exposure but does not replace rotation. If you want the IP fully out of circulation, a new server IP is the only complete fix.

## Changes made in this PR (tree only)

- `config/docker-compose.yml`: forwarders read `live/INGEST_STREAM_KEY` (filled in at deploy, like the platform keys); `TZ=UTC`.
- `scripts/multistream.sh`, `web/server.py`: deploy substitutes `INGEST_STREAM_KEY` (default `livestream`, so nothing breaks before you opt in), rejects values with characters other than letters, digits, `_` and `-`, and the CLI warns while the default is in use.
- `.env.example`, `README.md`, `web/templates/dashboard.html`: document the new variable instead of `livestream`.
- `.gitignore`: added `.env.*` (keeping `.env.example`), `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa*`, `id_ed25519*`, `id_ecdsa*`, `credentials*`, `secrets/`, `*.secret`, `docker-compose.override.yml`, `*.rendered.yml`, `__pycache__/`.

No history was rewritten, nothing was force-pushed, and no branches or tags were deleted.
