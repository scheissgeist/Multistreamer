#!/bin/bash
# Multistream management CLI
# Manages remote SRS + ffmpeg multistream server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file. Copy .env.example to .env and fill in your values."
    exit 1
fi

source "$ENV_FILE"
SSH="ssh root@$SERVER_IP"

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────

json_get() {
    python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

update_env_value() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

usage() {
    cat <<'EOF'
Usage: multistream.sh <command>

Server:
  status     Show server, SRS, and stunnel status
  logs       Tail SRS logs (ctrl+c to stop)
  restart    Restart SRS and stunnel
  deploy     Push local configs to server and restart
  streams    Show active streams via SRS API
  health     Quick health check (exit 0 = healthy)
  update     Pull latest SRS docker image and restart
  keys       Update stream keys from .env and restart

Stream metadata (requires API setup):
  golive "Title" --game "Game Name"
  title "New Title"
  game "Game Name"
EOF
    exit 1
}

# ─────────────────────────────────────────────
# SERVER COMMANDS
# ─────────────────────────────────────────────

cmd_status() {
    echo "=== Server ==="
    $SSH "uptime && echo '' && df -h / | tail -1"
    echo ""
    echo "=== Docker ==="
    $SSH "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    echo ""
    echo "=== Stunnel ==="
    $SSH "systemctl is-active stunnel4 && ss -tlnp | grep 1936 || echo 'NOT RUNNING'"
    echo ""
    echo "=== Bandwidth (this month) ==="
    $SSH "vnstat -m 2>/dev/null || echo 'vnstat not installed'"
}

cmd_logs() {
    $SSH "docker logs -f --tail 50 multistream-srs"
}

cmd_restart() {
    echo "Restarting services..."
    $SSH "cd /opt/multistream && docker compose restart && systemctl restart stunnel4"
    sleep 2
    cmd_status
}

cmd_deploy() {
    echo "Deploying configs to server..."

    # Substitute stream keys into docker-compose.yml
    local temp=$(mktemp)
    sed "s|TWITCH_STREAM_KEY|$TWITCH_STREAM_KEY|g; s|KICK_STREAM_KEY|$KICK_STREAM_KEY|g; s|RUMBLE_RTMP_URL|${RUMBLE_RTMP_URL:-RUMBLE_RTMP_URL}|g; s|RUMBLE_STREAM_KEY|${RUMBLE_STREAM_KEY:-RUMBLE_STREAM_KEY}|g; s|X_RTMP_URL|${X_RTMP_URL:-X_RTMP_URL}|g; s|X_STREAM_KEY|${X_STREAM_KEY:-X_STREAM_KEY}|g" \
        "$SCRIPT_DIR/../config/docker-compose.yml" > "$temp"
    scp "$temp" "root@$SERVER_IP:/opt/multistream/docker-compose.yml"
    rm "$temp"

    scp "$SCRIPT_DIR/../config/srs.conf" "root@$SERVER_IP:/opt/multistream/conf/srs.conf"
    scp "$SCRIPT_DIR/../config/kick-stunnel.conf" "root@$SERVER_IP:/etc/stunnel/kick.conf"

    echo "Restarting services..."
    $SSH "cd /opt/multistream && docker compose up -d && systemctl restart stunnel4"
    sleep 2
    cmd_status
}

cmd_streams() {
    echo "=== Active Streams ==="
    curl -s "http://$SERVER_IP:1985/api/v1/streams/" | python3 -m json.tool 2>/dev/null || \
        curl -s "http://$SERVER_IP:1985/api/v1/streams/"
}

cmd_health() {
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:1985/api/v1/summaries" --connect-timeout 5)
    if [ "$http_code" != "200" ]; then
        echo "UNHEALTHY: SRS API not responding (HTTP $http_code)"
        exit 1
    fi

    local stunnel
    stunnel=$($SSH "systemctl is-active stunnel4" 2>/dev/null)
    if [ "$stunnel" != "active" ]; then
        echo "UNHEALTHY: Stunnel not running"
        exit 1
    fi

    local container
    container=$($SSH "docker inspect -f '{{.State.Running}}' multistream-srs" 2>/dev/null)
    if [ "$container" != "true" ]; then
        echo "UNHEALTHY: SRS container not running"
        exit 1
    fi

    echo "HEALTHY: SRS + Stunnel running"
}

cmd_update() {
    echo "Pulling latest SRS image..."
    $SSH "cd /opt/multistream && docker compose pull && docker compose up -d"
    sleep 2
    cmd_status
}

cmd_keys() {
    cmd_deploy
}

# ─────────────────────────────────────────────
# API: TOKEN REFRESH
# ─────────────────────────────────────────────

refresh_twitch_token() {
    [ -z "${TWITCH_REFRESH_TOKEN:-}" ] && return 1

    local response new_token new_refresh
    response=$(curl -s -X POST 'https://id.twitch.tv/oauth2/token' \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${TWITCH_REFRESH_TOKEN}" \
        -d "client_id=${TWITCH_CLIENT_ID}" \
        -d "client_secret=${TWITCH_CLIENT_SECRET}")

    new_token=$(echo "$response" | json_get access_token)
    new_refresh=$(echo "$response" | json_get refresh_token)

    [ -z "$new_token" ] && return 1
    TWITCH_ACCESS_TOKEN="$new_token"
    TWITCH_REFRESH_TOKEN="$new_refresh"
    update_env_value "TWITCH_ACCESS_TOKEN" "$new_token"
    update_env_value "TWITCH_REFRESH_TOKEN" "$new_refresh"
}

refresh_kick_token() {
    [ -z "${KICK_REFRESH_TOKEN:-}" ] && return 1

    local response new_token new_refresh
    response=$(curl -s -X POST 'https://id.kick.com/oauth/token' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${KICK_REFRESH_TOKEN}" \
        -d "client_id=${KICK_CLIENT_ID}" \
        -d "client_secret=${KICK_CLIENT_SECRET}")

    new_token=$(echo "$response" | json_get access_token)
    new_refresh=$(echo "$response" | json_get refresh_token)

    [ -z "$new_token" ] && return 1
    KICK_ACCESS_TOKEN="$new_token"
    KICK_REFRESH_TOKEN="$new_refresh"
    update_env_value "KICK_ACCESS_TOKEN" "$new_token"
    update_env_value "KICK_REFRESH_TOKEN" "$new_refresh"
}

# ─────────────────────────────────────────────
# API: HTTP WRAPPERS (with auto-refresh on 401)
# ─────────────────────────────────────────────

# Usage: api_call <platform> <method> <url> [data]
# Platform: twitch or kick
api_call() {
    local platform="$1" method="$2" url="$3" data="${4:-}"

    local token client_id_header=""
    if [ "$platform" = "twitch" ]; then
        token="$TWITCH_ACCESS_TOKEN"
        client_id_header="-H Client-Id: $TWITCH_CLIENT_ID"
    else
        token="$KICK_ACCESS_TOKEN"
    fi

    local -a args=(-s -X "$method" "$url"
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json")
    [ "$platform" = "twitch" ] && args+=(-H "Client-Id: $TWITCH_CLIENT_ID")
    [ -n "$data" ] && args+=(-d "$data")

    local body http_code
    body=$(curl -w "\n%{http_code}" "${args[@]}")
    http_code=$(echo "$body" | tail -1)
    body=$(echo "$body" | head -n -1)

    # Auto-refresh on 401
    if [ "$http_code" = "401" ]; then
        if "refresh_${platform}_token"; then
            if [ "$platform" = "twitch" ]; then
                token="$TWITCH_ACCESS_TOKEN"
            else
                token="$KICK_ACCESS_TOKEN"
            fi
            # Rebuild auth header and retry
            args=(-s -X "$method" "$url"
                -H "Authorization: Bearer $token"
                -H "Content-Type: application/json")
            [ "$platform" = "twitch" ] && args+=(-H "Client-Id: $TWITCH_CLIENT_ID")
            [ -n "$data" ] && args+=(-d "$data")
            body=$(curl -w "\n%{http_code}" "${args[@]}")
            http_code=$(echo "$body" | tail -1)
            body=$(echo "$body" | head -n -1)
        fi
    fi

    echo "$body"
    [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]
}

# ─────────────────────────────────────────────
# API: STREAM METADATA
# ─────────────────────────────────────────────

lookup_twitch_game() {
    local encoded
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$1'''))")
    api_call twitch GET "https://api.twitch.tv/helix/search/categories?query=${encoded}" | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
cats = data.get('data', [])
q = sys.argv[1].lower()
for c in cats:
    if c['name'].lower() == q:
        print(c['id']); sys.exit(0)
if cats:
    print(cats[0]['id'])
" "$1" 2>/dev/null
}

lookup_kick_category() {
    local encoded
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$1'''))")
    api_call kick GET "https://api.kick.com/public/v1/categories?q=${encoded}" | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
cats = data.get('data', [])
q = sys.argv[1].lower()
for c in cats:
    if c['name'].lower() == q:
        print(c['id']); sys.exit(0)
if cats:
    print(cats[0]['id'])
" "$1" 2>/dev/null
}

check_api_auth() {
    local missing=""
    [ -z "${TWITCH_ACCESS_TOKEN:-}" ] && missing="Twitch"
    if [ -z "${KICK_ACCESS_TOKEN:-}" ]; then
        [ -n "$missing" ] && missing="$missing + "
        missing="${missing}Kick"
    fi
    if [ -n "$missing" ]; then
        echo "Missing API tokens for: $missing"
        echo "Run: bash scripts/auth-setup.sh"
        exit 1
    fi
}

set_twitch_info() {
    local title="$1" game_id="$2"
    local body="{"
    local comma=false
    if [ -n "$title" ]; then
        body="${body}\"title\":\"${title}\""
        comma=true
    fi
    if [ -n "$game_id" ]; then
        $comma && body="${body},"
        body="${body}\"game_id\":\"${game_id}\""
    fi
    body="${body}}"
    api_call twitch PATCH "https://api.twitch.tv/helix/channels?broadcaster_id=${TWITCH_BROADCASTER_ID}" "$body" > /dev/null
}

set_kick_info() {
    local title="$1" category_id="$2"
    local body="{"
    local comma=false
    if [ -n "$title" ]; then
        body="${body}\"stream_title\":\"${title}\""
        comma=true
    fi
    if [ -n "$category_id" ]; then
        $comma && body="${body},"
        body="${body}\"category_id\":${category_id}"
    fi
    body="${body}}"
    api_call kick PATCH "https://api.kick.com/public/v1/channels" "$body" > /dev/null
}

# ─────────────────────────────────────────────
# COMMANDS: STREAM METADATA
# ─────────────────────────────────────────────

cmd_golive() {
    check_api_auth
    local title="" game=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --game|-g) shift; game="$1" ;;
            *) [ -z "$title" ] && title="$1" ;;
        esac
        shift
    done

    if [ -z "$title" ] && [ -z "$game" ]; then
        echo "Usage: multistream.sh golive \"Title\" --game \"Game Name\""
        exit 1
    fi

    local twitch_game_id="" kick_category_id=""
    if [ -n "$game" ]; then
        echo "Looking up \"$game\"..."
        twitch_game_id=$(lookup_twitch_game "$game")
        kick_category_id=$(lookup_kick_category "$game")
        [ -n "$twitch_game_id" ] && echo "  Twitch: found (ID: $twitch_game_id)" || echo "  Twitch: not found"
        [ -n "$kick_category_id" ] && echo "  Kick: found (ID: $kick_category_id)" || echo "  Kick: not found"
    fi

    echo ""
    if set_twitch_info "$title" "$twitch_game_id"; then
        echo "Twitch: updated"
    else
        echo "Twitch: FAILED"
    fi

    if set_kick_info "$title" "$kick_category_id"; then
        echo "Kick: updated"
    else
        echo "Kick: FAILED"
    fi
}

cmd_title() {
    [ -z "${1:-}" ] && { echo "Usage: multistream.sh title \"New Title\""; exit 1; }
    check_api_auth
    set_twitch_info "$1" "" && echo "Twitch: title set" || echo "Twitch: FAILED"
    set_kick_info "$1" "" && echo "Kick: title set" || echo "Kick: FAILED"
}

cmd_game() {
    [ -z "${1:-}" ] && { echo "Usage: multistream.sh game \"Game Name\""; exit 1; }
    check_api_auth
    local game="$1"
    echo "Looking up \"$game\"..."

    local twitch_game_id kick_category_id
    twitch_game_id=$(lookup_twitch_game "$game")
    kick_category_id=$(lookup_kick_category "$game")

    if [ -n "$twitch_game_id" ]; then
        set_twitch_info "" "$twitch_game_id" && echo "Twitch: $game (ID: $twitch_game_id)" || echo "Twitch: FAILED"
    else
        echo "Twitch: \"$game\" not found"
    fi

    if [ -n "$kick_category_id" ]; then
        set_kick_info "" "$kick_category_id" && echo "Kick: $game (ID: $kick_category_id)" || echo "Kick: FAILED"
    else
        echo "Kick: \"$game\" not found"
    fi
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

case "${1:-}" in
    status)  cmd_status ;;
    logs)    cmd_logs ;;
    restart) cmd_restart ;;
    deploy)  cmd_deploy ;;
    streams) cmd_streams ;;
    health)  cmd_health ;;
    update)  cmd_update ;;
    keys)    cmd_keys ;;
    golive)  shift; cmd_golive "$@" ;;
    title)   shift; cmd_title "$@" ;;
    game)    shift; cmd_game "$@" ;;
    *)       usage ;;
esac
