#!/bin/bash
# One-time OAuth setup for Twitch and Kick APIs
# Run this once, tokens get saved to .env

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Missing .env file. Copy .env.example to .env first."
    exit 1
fi

source "$ENV_FILE"

# ─────────────────────────────────────────────
# TWITCH SETUP
# ─────────────────────────────────────────────

setup_twitch() {
    echo ""
    echo "=== TWITCH API SETUP ==="
    echo ""

    if [ -z "$TWITCH_CLIENT_ID" ] || [ -z "$TWITCH_CLIENT_SECRET" ]; then
        echo "First, register an app at https://dev.twitch.tv/console/apps"
        echo "  - Name: Multistreamer (or whatever)"
        echo "  - OAuth Redirect URL: http://localhost:3000"
        echo "  - Category: Broadcaster Suite"
        echo ""
        read -p "Client ID: " TWITCH_CLIENT_ID
        read -p "Client Secret: " TWITCH_CLIENT_SECRET
    else
        echo "Client ID found: ${TWITCH_CLIENT_ID:0:8}..."
    fi

    # Use authorization code flow
    SCOPES="channel:manage:broadcast"
    AUTH_URL="https://id.twitch.tv/oauth2/authorize?response_type=code&client_id=${TWITCH_CLIENT_ID}&redirect_uri=http://localhost:3000&scope=${SCOPES}&state=multistreamer"

    echo ""
    echo "Open this URL in your browser:"
    echo ""
    echo "  $AUTH_URL"
    echo ""
    echo "After authorizing, you'll be redirected to localhost:3000 (it'll fail to load)."
    echo "Copy the 'code' parameter from the URL bar."
    echo "It looks like: http://localhost:3000?code=XXXXXX&scope=...&state=..."
    echo ""
    read -p "Paste the code: " AUTH_CODE

    # Exchange code for token
    RESPONSE=$(curl -s -X POST 'https://id.twitch.tv/oauth2/token' \
        -d "client_id=${TWITCH_CLIENT_ID}" \
        -d "client_secret=${TWITCH_CLIENT_SECRET}" \
        -d "code=${AUTH_CODE}" \
        -d "grant_type=authorization_code" \
        -d "redirect_uri=http://localhost:3000")

    TWITCH_ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    TWITCH_REFRESH_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null)

    if [ -z "$TWITCH_ACCESS_TOKEN" ]; then
        echo "ERROR: Failed to get token. Response:"
        echo "$RESPONSE"
        return 1
    fi

    # Get broadcaster ID
    TWITCH_BROADCASTER_ID=$(curl -s -G 'https://api.twitch.tv/helix/users' \
        -H "Authorization: Bearer $TWITCH_ACCESS_TOKEN" \
        -H "Client-Id: $TWITCH_CLIENT_ID" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)

    echo ""
    echo "Twitch auth successful! Broadcaster ID: $TWITCH_BROADCASTER_ID"

    # Save to .env
    update_env "TWITCH_CLIENT_ID" "$TWITCH_CLIENT_ID"
    update_env "TWITCH_CLIENT_SECRET" "$TWITCH_CLIENT_SECRET"
    update_env "TWITCH_ACCESS_TOKEN" "$TWITCH_ACCESS_TOKEN"
    update_env "TWITCH_REFRESH_TOKEN" "$TWITCH_REFRESH_TOKEN"
    update_env "TWITCH_BROADCASTER_ID" "$TWITCH_BROADCASTER_ID"
}

# ─────────────────────────────────────────────
# KICK SETUP
# ─────────────────────────────────────────────

setup_kick() {
    echo ""
    echo "=== KICK API SETUP ==="
    echo ""

    if [ -z "$KICK_CLIENT_ID" ] || [ -z "$KICK_CLIENT_SECRET" ]; then
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
    # Generate code verifier and challenge
    CODE_VERIFIER=$(python3 -c "import secrets; print(secrets.token_urlsafe(64)[:128])")
    CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')

    SCOPES="channel:write"
    AUTH_URL="https://id.kick.com/oauth/authorize?response_type=code&client_id=${KICK_CLIENT_ID}&redirect_uri=http://localhost:3000&scope=${SCOPES}&state=multistreamer&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"

    echo ""
    echo "Open this URL in your browser:"
    echo ""
    echo "  $AUTH_URL"
    echo ""
    echo "After authorizing, copy the 'code' parameter from the redirect URL."
    echo ""
    read -p "Paste the code: " AUTH_CODE

    # Exchange code for token (with PKCE verifier)
    RESPONSE=$(curl -s -X POST 'https://id.kick.com/oauth/token' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d "grant_type=authorization_code" \
        -d "client_id=${KICK_CLIENT_ID}" \
        -d "client_secret=${KICK_CLIENT_SECRET}" \
        -d "redirect_uri=http://localhost:3000" \
        -d "code=${AUTH_CODE}" \
        -d "code_verifier=${CODE_VERIFIER}")

    KICK_ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    KICK_REFRESH_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))" 2>/dev/null)

    if [ -z "$KICK_ACCESS_TOKEN" ]; then
        echo "ERROR: Failed to get token. Response:"
        echo "$RESPONSE"
        return 1
    fi

    echo ""
    echo "Kick auth successful!"

    # Save to .env
    update_env "KICK_CLIENT_ID" "$KICK_CLIENT_ID"
    update_env "KICK_CLIENT_SECRET" "$KICK_CLIENT_SECRET"
    update_env "KICK_ACCESS_TOKEN" "$KICK_ACCESS_TOKEN"
    update_env "KICK_REFRESH_TOKEN" "$KICK_REFRESH_TOKEN"
    update_env "KICK_CODE_VERIFIER" "$CODE_VERIFIER"
}

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────

update_env() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        # Update existing line
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    elif grep -q "^# *${key}=" "$ENV_FILE" 2>/dev/null; then
        # Uncomment and set
        sed -i "s|^# *${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        # Append
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

case "${1:-all}" in
    twitch)  setup_twitch ;;
    kick)    setup_kick ;;
    all)
        setup_twitch
        echo ""
        echo "─────────────────────────────────────────"
        setup_kick
        echo ""
        echo "=== DONE ==="
        echo "Tokens saved to .env"
        echo "You can now use: bash scripts/multistream.sh golive \"Your Title\" --game \"Game Name\""
        ;;
    *)
        echo "Usage: auth-setup.sh [twitch|kick|all]"
        exit 1
        ;;
esac
