#!/bin/bash
# One-time OAuth setup for Twitch and Kick APIs
# Saves tokens to .env for use by multistream.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file. Copy .env.example to .env first."
    exit 1
fi

source "$ENV_FILE"

update_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    elif grep -q "^# *${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^# *${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

json_get() {
    python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

# ─────────────────────────────────────────────
# TWITCH
# ─────────────────────────────────────────────

setup_twitch() {
    echo ""
    echo "=== TWITCH API SETUP ==="
    echo ""

    if [ -z "${TWITCH_CLIENT_ID:-}" ] || [ -z "${TWITCH_CLIENT_SECRET:-}" ]; then
        echo "Register an app at https://dev.twitch.tv/console/apps"
        echo "  - Redirect URL: http://localhost:3000"
        echo "  - Category: Broadcaster Suite"
        echo ""
        read -p "Client ID: " TWITCH_CLIENT_ID
        read -p "Client Secret: " TWITCH_CLIENT_SECRET
    else
        echo "Client ID found: ${TWITCH_CLIENT_ID:0:8}..."
    fi

    local auth_url="https://id.twitch.tv/oauth2/authorize?response_type=code&client_id=${TWITCH_CLIENT_ID}&redirect_uri=http://localhost:3000&scope=channel:manage:broadcast&state=multistreamer"

    echo ""
    echo "Open this URL in your browser:"
    echo ""
    echo "  $auth_url"
    echo ""
    echo "After authorizing, copy the 'code' parameter from the redirect URL."
    echo ""
    read -p "Paste the code: " AUTH_CODE

    local response
    response=$(curl -s -X POST 'https://id.twitch.tv/oauth2/token' \
        -d "client_id=${TWITCH_CLIENT_ID}" \
        -d "client_secret=${TWITCH_CLIENT_SECRET}" \
        -d "code=${AUTH_CODE}" \
        -d "grant_type=authorization_code" \
        -d "redirect_uri=http://localhost:3000")

    TWITCH_ACCESS_TOKEN=$(echo "$response" | json_get access_token)
    TWITCH_REFRESH_TOKEN=$(echo "$response" | json_get refresh_token)

    if [ -z "$TWITCH_ACCESS_TOKEN" ]; then
        echo "ERROR: Failed to get token. Response:"
        echo "$response"
        return 1
    fi

    TWITCH_BROADCASTER_ID=$(curl -s -G 'https://api.twitch.tv/helix/users' \
        -H "Authorization: Bearer $TWITCH_ACCESS_TOKEN" \
        -H "Client-Id: $TWITCH_CLIENT_ID" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)

    echo ""
    echo "Twitch auth successful! Broadcaster ID: $TWITCH_BROADCASTER_ID"

    update_env "TWITCH_CLIENT_ID" "$TWITCH_CLIENT_ID"
    update_env "TWITCH_CLIENT_SECRET" "$TWITCH_CLIENT_SECRET"
    update_env "TWITCH_ACCESS_TOKEN" "$TWITCH_ACCESS_TOKEN"
    update_env "TWITCH_REFRESH_TOKEN" "$TWITCH_REFRESH_TOKEN"
    update_env "TWITCH_BROADCASTER_ID" "$TWITCH_BROADCASTER_ID"
}

# ─────────────────────────────────────────────
# KICK
# ─────────────────────────────────────────────

setup_kick() {
    echo ""
    echo "=== KICK API SETUP ==="
    echo ""

    if [ -z "${KICK_CLIENT_ID:-}" ] || [ -z "${KICK_CLIENT_SECRET:-}" ]; then
        echo "Register an app at https://dev.kick.com"
        echo "  - Redirect URI: http://localhost:3000"
        echo "  - Scopes: channel:write"
        echo ""
        read -p "Client ID: " KICK_CLIENT_ID
        read -p "Client Secret: " KICK_CLIENT_SECRET
    else
        echo "Client ID found: ${KICK_CLIENT_ID:0:8}..."
    fi

    # Kick uses OAuth 2.1 with PKCE (S256)
    local code_verifier code_challenge
    code_verifier=$(python3 -c "import secrets; print(secrets.token_urlsafe(64)[:128])")
    code_challenge=$(printf '%s' "$code_verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')

    local auth_url="https://id.kick.com/oauth/authorize?response_type=code&client_id=${KICK_CLIENT_ID}&redirect_uri=http://localhost:3000&scope=channel:write&state=multistreamer&code_challenge=${code_challenge}&code_challenge_method=S256"

    echo ""
    echo "Open this URL in your browser:"
    echo ""
    echo "  $auth_url"
    echo ""
    echo "After authorizing, copy the 'code' parameter from the redirect URL."
    echo ""
    read -p "Paste the code: " AUTH_CODE

    local response
    response=$(curl -s -X POST 'https://id.kick.com/oauth/token' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d "grant_type=authorization_code" \
        -d "client_id=${KICK_CLIENT_ID}" \
        -d "client_secret=${KICK_CLIENT_SECRET}" \
        -d "redirect_uri=http://localhost:3000" \
        -d "code=${AUTH_CODE}" \
        -d "code_verifier=${code_verifier}")

    KICK_ACCESS_TOKEN=$(echo "$response" | json_get access_token)
    KICK_REFRESH_TOKEN=$(echo "$response" | json_get refresh_token)

    if [ -z "$KICK_ACCESS_TOKEN" ]; then
        echo "ERROR: Failed to get token. Response:"
        echo "$response"
        return 1
    fi

    echo ""
    echo "Kick auth successful!"

    update_env "KICK_CLIENT_ID" "$KICK_CLIENT_ID"
    update_env "KICK_CLIENT_SECRET" "$KICK_CLIENT_SECRET"
    update_env "KICK_ACCESS_TOKEN" "$KICK_ACCESS_TOKEN"
    update_env "KICK_REFRESH_TOKEN" "$KICK_REFRESH_TOKEN"
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

case "${1:-all}" in
    twitch) setup_twitch ;;
    kick)   setup_kick ;;
    all)
        setup_twitch
        echo ""
        echo "─────────────────────────────────────────"
        setup_kick
        echo ""
        echo "=== DONE ==="
        echo "Tokens saved to .env"
        echo "You can now use: bash scripts/multistream.sh golive \"Title\" --game \"Game Name\""
        ;;
    *)
        echo "Usage: auth-setup.sh [twitch|kick|all]"
        exit 1
        ;;
esac
