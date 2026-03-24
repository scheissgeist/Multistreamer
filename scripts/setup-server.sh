#!/usr/bin/env bash
# setup-server.sh — Provision a fresh VPS for multistreaming
# Run this ON the remote server after SSHing in:
#   curl -fsSL <url> | bash   OR   bash setup-server.sh
#
# Idempotent: safe to run multiple times.

set -euo pipefail

echo "=== Multistream Server Setup ==="
echo ""

# ---------------------------------------------------------------------------
# 1. Install Docker + docker-compose
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null; then
    echo "[OK] Docker already installed: $(docker --version)"
else
    echo "[*] Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    echo "[OK] Docker installed."
fi

if command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
    echo "[OK] docker-compose available."
else
    echo "[*] Installing docker-compose standalone..."
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "[OK] docker-compose installed."
fi

# ---------------------------------------------------------------------------
# 2. Install stunnel4 (for Kick RTMPS)
# ---------------------------------------------------------------------------
if command -v stunnel4 &>/dev/null || command -v stunnel &>/dev/null; then
    echo "[OK] stunnel already installed."
else
    echo "[*] Installing stunnel4..."
    apt-get install -y -qq stunnel4
    echo "[OK] stunnel4 installed."
fi

# ---------------------------------------------------------------------------
# 3. Create /opt/multistream directory structure
# ---------------------------------------------------------------------------
echo "[*] Creating /opt/multistream directory structure..."
mkdir -p /opt/multistream/conf
mkdir -p /opt/multistream/logs
echo "[OK] Directory structure ready."

# ---------------------------------------------------------------------------
# 4. Write SRS config
# ---------------------------------------------------------------------------
echo "[*] Writing SRS config..."
cat > /opt/multistream/conf/srs.conf << 'SRSCONF'
# SRS Configuration — RTMP ingest only
# Forwarding is handled by ffmpeg containers (see docker-compose.yml)

listen              1935;
max_connections     100;
daemon              off;
srs_log_tank        console;

http_server {
    enabled         on;
    listen          8080;
    dir             ./objs/nginx/html;
}

http_api {
    enabled         on;
    listen          1985;
}

stats {
    network         0;
}

vhost __defaultVhost__ {
    hls {
        enabled         on;
        hls_fragment    2;
        hls_window      10;
        hls_path        ./objs/nginx/html;
        hls_m3u8_file   [app]/[stream].m3u8;
        hls_ts_file     [app]/[stream]-[seq].ts;
    }
}
SRSCONF
echo "[OK] SRS config written to /opt/multistream/conf/srs.conf"

# ---------------------------------------------------------------------------
# 5. Set up stunnel for Kick RTMPS
# ---------------------------------------------------------------------------
echo "[*] Configuring stunnel for Kick RTMPS..."

# Ensure stunnel pid directory exists
mkdir -p /var/run/stunnel4

cat > /etc/stunnel/kick.conf << 'STUNCONF'
; Stunnel config for Kick RTMPS
; Listens on localhost:1936, wraps in TLS, forwards to Kick's RTMP ingest

pid = /var/run/stunnel4/stunnel.pid

[kick]
client = yes
accept = 127.0.0.1:1936
connect = global-contribute.live-video.net:443
verifyChain = no
STUNCONF

# Enable stunnel to start on boot
if [ -f /etc/default/stunnel4 ]; then
    sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4
fi

# Start or restart stunnel
systemctl enable stunnel4 2>/dev/null || true
systemctl restart stunnel4 2>/dev/null || stunnel4 /etc/stunnel/kick.conf || true
echo "[OK] stunnel configured on 127.0.0.1:1936 -> Kick RTMPS"

# ---------------------------------------------------------------------------
# 6. Open firewall ports
# ---------------------------------------------------------------------------
echo "[*] Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw allow 22/tcp    comment "SSH"       >/dev/null 2>&1 || true
    ufw allow 1935/tcp  comment "RTMP"      >/dev/null 2>&1 || true
    ufw allow 8080/tcp  comment "HTTP/HLS"  >/dev/null 2>&1 || true
    ufw allow 1985/tcp  comment "SRS API"   >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    echo "[OK] ufw rules set (22, 1935, 8080, 1985)."
else
    echo "[SKIP] ufw not found. If using a cloud firewall, open ports 1935, 8080, 1985 manually."
fi

# ---------------------------------------------------------------------------
# 7. Install vnstat for bandwidth monitoring
# ---------------------------------------------------------------------------
if command -v vnstat &>/dev/null; then
    echo "[OK] vnstat already installed."
else
    echo "[*] Installing vnstat..."
    apt-get install -y -qq vnstat
    systemctl enable vnstat 2>/dev/null || true
    systemctl start vnstat 2>/dev/null || true
    echo "[OK] vnstat installed."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Server ready!"
echo "========================================"
echo ""
echo "  Configs written:"
echo "    /opt/multistream/conf/srs.conf"
echo "    /etc/stunnel/kick.conf"
echo ""
echo "  Next: Go back to your local machine and run the dashboard:"
echo "    python web/server.py"
echo "  Then enter this server's IP in the dashboard."
echo ""
echo "  To start manually without the dashboard:"
echo "    cd /opt/multistream"
echo "    docker compose up -d"
echo ""
