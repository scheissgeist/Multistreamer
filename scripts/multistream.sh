#!/bin/bash
# Multistream management script
# Run from local machine to manage the remote server

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file. Copy .env.example to .env and fill in your keys."
    exit 1
fi

source "$ENV_FILE"
SSH="ssh root@$SERVER_IP"

usage() {
    echo "Usage: multistream.sh <command>"
    echo ""
    echo "Commands:"
    echo "  status     Show server, SRS, and stunnel status"
    echo "  logs       Tail SRS logs (ctrl+c to stop)"
    echo "  restart    Restart SRS and stunnel"
    echo "  deploy     Push local configs to server and restart"
    echo "  streams    Show active streams via SRS API"
    echo "  health     Quick health check (exit 0 = healthy)"
    echo "  update     Pull latest SRS docker image and restart"
    echo "  keys       Update stream keys from .env and restart"
    echo ""
    echo "  golive \"Title\" --game \"Game Name\"   Set title/game on Twitch + Kick"
    echo "  title \"New Title\"                    Update title only (both platforms)"
    echo "  game \"Game Name\"                     Update game/category only (both platforms)"
    exit 1
}

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
    echo "Restarting SRS..."
    $SSH "cd /opt/multistream && docker compose restart"
    echo "Restarting Stunnel..."
    $SSH "systemctl restart stunnel4"
    echo "Done. Checking status..."
    sleep 2
    cmd_status
}

cmd_deploy() {
    echo "Deploying configs to server..."
    scp "$SCRIPT_DIR/../config/docker-compose.yml" "root@$SERVER_IP:/opt/multistream/docker-compose.yml"
    scp "$SCRIPT_DIR/../config/kick-stunnel.conf" "root@$SERVER_IP:/etc/stunnel/kick.conf"

    # Build srs.conf with real keys from .env
    TEMP_CONF=$(mktemp)
    sed "s|TWITCH_STREAM_KEY|$TWITCH_STREAM_KEY|g" "$SCRIPT_DIR/../config/srs.conf" \
        | sed "s|KICK_STREAM_KEY|$KICK_STREAM_KEY|g" \
        > "$TEMP_CONF"

    if [ -n "$YOUTUBE_STREAM_KEY" ]; then
        sed -i "s|# destination     rtmp://a.rtmp.youtube.com/live2/YOUTUBE_STREAM_KEY;|destination     rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY;|g" "$TEMP_CONF"
    fi

    scp "$TEMP_CONF" "root@$SERVER_IP:/opt/multistream/conf/srs.conf"
    rm "$TEMP_CONF"

    echo "Restarting services..."
    $SSH "cd /opt/multistream && docker compose up -d && systemctl restart stunnel4"
    echo "Deploy complete."
    sleep 2
    cmd_status
}

cmd_streams() {
    echo "=== Active Streams ==="
    curl -s "http://$SERVER_IP:1985/api/v1/streams/" | python3 -m json.tool 2>/dev/null || \
    curl -s "http://$SERVER_IP:1985/api/v1/streams/" | python -m json.tool 2>/dev/null || \
    curl -s "http://$SERVER_IP:1985/api/v1/streams/"
}

cmd_health() {
    # Check SRS is responding
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:1985/api/v1/summaries" --connect-timeout 5)
    if [ "$HTTP_CODE" != "200" ]; then
        echo "UNHEALTHY: SRS API not responding (HTTP $HTTP_CODE)"
        exit 1
    fi

    # Check stunnel is listening
    STUNNEL=$($SSH "systemctl is-active stunnel4" 2>/dev/null)
    if [ "$STUNNEL" != "active" ]; then
        echo "UNHEALTHY: Stunnel not running"
        exit 1
    fi

    # Check docker container
    CONTAINER=$($SSH "docker inspect -f '{{.State.Running}}' multistream-srs" 2>/dev/null)
    if [ "$CONTAINER" != "true" ]; then
        echo "UNHEALTHY: SRS container not running"
        exit 1
    fi

    echo "HEALTHY: SRS + Stunnel running"
    exit 0
}

cmd_update() {
    echo "Pulling latest SRS image..."
    $SSH "cd /opt/multistream && docker compose pull && docker compose up -d"
    echo "Update complete."
    sleep 2
    cmd_status
}

cmd_keys() {
    echo "Updating stream keys from .env..."
    cmd_deploy
}

# ─────────────────────────────────────────────
# STREAM INFO (TITLE / GAME)
# ─────────────────────────────────────────────

update_env_value() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

refresh_twitch_token() {
    if [ -z "$TWITCH_REFRESH_TOKEN" ]; then return 1; fi

    RESPONSE=$(curl -s -X POST 'https://id.twitch.tv/oauth2/token' \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${TWITCH_REFRESH_TOKEN}" \
        -d "client_id=${TWITCH_CLIENT_ID}" \
        -d "client_secret=${TWITCH_CLIENT_SECRET}")

    NEW_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    NEW_REFRESH=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null)

    if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "" ]; then
        TWITCH_ACCESS_TOKEN="$NEW_TOKEN"
        TWITCH_REFRESH_TOKEN="$NEW_REFRESH"
        update_env_value "TWITCH_ACCESS_TOKEN" "$NEW_TOKEN"
        update_env_value "TWITCH_REFRESH_TOKEN" "$NEW_REFRESH"
        return 0
    fi
    return 1
}

refresh_kick_token() {
    if [ -z "$KICK_REFRESH_TOKEN" ]; then return 1; fi

    RESPONSE=$(curl -s -X POST 'https://id.kick.com/oauth/token' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${KICK_REFRESH_TOKEN}" \
        -d "client_id=${KICK_CLIENT_ID}" \
        -d "client_secret=${KICK_CLIENT_SECRET}")

    NEW_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    NEW_REFRESH=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null)

    if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "" ]; then
        KICK_ACCESS_TOKEN="$NEW_TOKEN"
        KICK_REFRESH_TOKEN="$NEW_REFRESH"
        update_env_value "KICK_ACCESS_TOKEN" "$NEW_TOKEN"
        update_env_value "KICK_REFRESH_TOKEN" "$NEW_REFRESH"
        return 0
    fi
    return 1
}

twitch_api() {
    local method="$1"
    local url="$2"
    local data="$3"

    local args=(-s -X "$method" "$url" \
        -H "Authorization: Bearer $TWITCH_ACCESS_TOKEN" \
        -H "Client-Id: $TWITCH_CLIENT_ID" \
        -H "Content-Type: application/json")

    if [ -n "$data" ]; then
        args+=(-d "$data")
    fi

    local HTTP_CODE
    local BODY
    BODY=$(curl -w "\n%{http_code}" "${args[@]}")
    HTTP_CODE=$(echo "$BODY" | tail -1)
    BODY=$(echo "$BODY" | head -n -1)

    # If 401, try refresh and retry once
    if [ "$HTTP_CODE" = "401" ]; then
        if refresh_twitch_token; then
            args[4]="Authorization: Bearer $TWITCH_ACCESS_TOKEN"
            BODY=$(curl -w "\n%{http_code}" "${args[@]}")
            HTTP_CODE=$(echo "$BODY" | tail -1)
            BODY=$(echo "$BODY" | head -n -1)
        fi
    fi

    echo "$BODY"
    return $([ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] && echo 0 || echo 1)
}

kick_api() {
    local method="$1"
    local url="$2"
    local data="$3"

    local args=(-s -X "$method" "$url" \
        -H "Authorization: Bearer $KICK_ACCESS_TOKEN" \
        -H "Content-Type: application/json")

    if [ -n "$data" ]; then
        args+=(-d "$data")
    fi

    local HTTP_CODE
    local BODY
    BODY=$(curl -w "\n%{http_code}" "${args[@]}")
    HTTP_CODE=$(echo "$BODY" | tail -1)
    BODY=$(echo "$BODY" | head -n -1)

    # If 401, try refresh and retry once
    if [ "$HTTP_CODE" = "401" ]; then
        if refresh_kick_token; then
            args[4]="Authorization: Bearer $KICK_ACCESS_TOKEN"
            BODY=$(curl -w "\n%{http_code}" "${args[@]}")
            HTTP_CODE=$(echo "$BODY" | tail -1)
            BODY=$(echo "$BODY" | head -n -1)
        fi
    fi

    echo "$BODY"
    return $([ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] && echo 0 || echo 1)
}

lookup_twitch_game() {
    local game_name="$1"
    local encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$game_name'))")
    local result
    result=$(twitch_api GET "https://api.twitch.tv/helix/search/categories?query=${encoded}")
    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
cats = data.get('data', [])
# Try exact match first
for c in cats:
    if c['name'].lower() == sys.argv[1].lower():
        print(c['id']); sys.exit(0)
# Fall back to first result
if cats:
    print(cats[0]['id'])
" "$game_name" 2>/dev/null
}

lookup_kick_category() {
    local game_name="$1"
    local encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$game_name'))")
    local result
    result=$(kick_api GET "https://api.kick.com/public/v1/categories?q=${encoded}")
    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
cats = data.get('data', [])
for c in cats:
    if c['name'].lower() == sys.argv[1].lower():
        print(c['id']); sys.exit(0)
if cats:
    print(cats[0]['id'])
" "$game_name" 2>/dev/null
}

check_api_auth() {
    local missing=""
    if [ -z "$TWITCH_ACCESS_TOKEN" ]; then missing="Twitch"; fi
    if [ -z "$KICK_ACCESS_TOKEN" ]; then
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
    local title="$1"
    local game_id="$2"

    local body="{"
    local need_comma=false
    if [ -n "$title" ]; then
        body="${body}\"title\":\"${title}\""
        need_comma=true
    fi
    if [ -n "$game_id" ]; then
        $need_comma && body="${body},"
        body="${body}\"game_id\":\"${game_id}\""
    fi
    body="${body}}"

    twitch_api PATCH "https://api.twitch.tv/helix/channels?broadcaster_id=${TWITCH_BROADCASTER_ID}" "$body" > /dev/null
    return $?
}

set_kick_info() {
    local title="$1"
    local category_id="$2"

    local body="{"
    local need_comma=false
    if [ -n "$title" ]; then
        body="${body}\"stream_title\":\"${title}\""
        need_comma=true
    fi
    if [ -n "$category_id" ]; then
        $need_comma && body="${body},"
        body="${body}\"category_id\":${category_id}"
    fi
    body="${body}}"

    kick_api PATCH "https://api.kick.com/public/v1/channels" "$body" > /dev/null
    return $?
}

cmd_golive() {
    check_api_auth

    local title=""
    local game=""

    # Parse args: golive "Title" --game "Game Name"
    while [ $# -gt 0 ]; do
        case "$1" in
            --game|-g)
                shift
                game="$1"
                ;;
            *)
                if [ -z "$title" ]; then
                    title="$1"
                fi
                ;;
        esac
        shift
    done

    if [ -z "$title" ] && [ -z "$game" ]; then
        echo "Usage: multistream.sh golive \"Stream Title\" --game \"Game Name\""
        echo "       multistream.sh golive \"Stream Title\""
        echo "       multistream.sh golive --game \"Game Name\""
        exit 1
    fi

    local twitch_game_id=""
    local kick_category_id=""

    if [ -n "$game" ]; then
        echo "Looking up \"$game\"..."
        twitch_game_id=$(lookup_twitch_game "$game")
        kick_category_id=$(lookup_kick_category "$game")

        if [ -z "$twitch_game_id" ]; then
            echo "  Twitch: game not found"
        else
            echo "  Twitch: found (ID: $twitch_game_id)"
        fi

        if [ -z "$kick_category_id" ]; then
            echo "  Kick: category not found"
        else
            echo "  Kick: found (ID: $kick_category_id)"
        fi
    fi

    echo ""

    # Set Twitch
    if set_twitch_info "$title" "$twitch_game_id"; then
        echo "Twitch: updated"
        [ -n "$title" ] && echo "  Title: $title"
        [ -n "$game" ] && echo "  Game: $game"
    else
        echo "Twitch: FAILED"
    fi

    # Set Kick
    if set_kick_info "$title" "$kick_category_id"; then
        echo "Kick: updated"
        [ -n "$title" ] && echo "  Title: $title"
        [ -n "$game" ] && echo "  Game: $game"
    else
        echo "Kick: FAILED"
    fi

    echo ""
    echo "Ready to stream. Hit Start Streaming in OBS."
}

cmd_title() {
    if [ -z "$1" ]; then
        echo "Usage: multistream.sh title \"New Title\""
        exit 1
    fi
    check_api_auth
    local title="$1"

    if set_twitch_info "$title" ""; then
        echo "Twitch: title set to \"$title\""
    else
        echo "Twitch: FAILED"
    fi

    if set_kick_info "$title" ""; then
        echo "Kick: title set to \"$title\""
    else
        echo "Kick: FAILED"
    fi
}

cmd_game() {
    if [ -z "$1" ]; then
        echo "Usage: multistream.sh game \"Game Name\""
        exit 1
    fi
    check_api_auth
    local game="$1"

    echo "Looking up \"$game\"..."

    local twitch_game_id=$(lookup_twitch_game "$game")
    local kick_category_id=$(lookup_kick_category "$game")

    if [ -n "$twitch_game_id" ]; then
        if set_twitch_info "" "$twitch_game_id"; then
            echo "Twitch: game set to \"$game\" (ID: $twitch_game_id)"
        else
            echo "Twitch: FAILED to set game"
        fi
    else
        echo "Twitch: game \"$game\" not found"
    fi

    if [ -n "$kick_category_id" ]; then
        if set_kick_info "" "$kick_category_id"; then
            echo "Kick: category set to \"$game\" (ID: $kick_category_id)"
        else
            echo "Kick: FAILED to set category"
        fi
    else
        echo "Kick: category \"$game\" not found"
    fi
}

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
