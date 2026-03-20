#!/usr/bin/env python3
"""Multistreamer Web Dashboard — local control panel for your multistream server."""

import json
import os
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)

# Load .env
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
env = {}


def load_env():
    global env
    env.clear()
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()


def save_env_value(key, value):
    load_env()
    env[key] = value
    lines = []
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#") and "=" in stripped:
                k = stripped.split("=", 1)[0].strip()
                if k == key:
                    lines.append(f"{key}={value}")
                    continue
            lines.append(line)
        if key not in [l.split("=", 1)[0].strip() for l in lines if "=" in l and not l.strip().startswith("#")]:
            lines.append(f"{key}={value}")
    else:
        lines.append(f"{key}={value}")
    ENV_FILE.write_text("\n".join(lines) + "\n")


def ssh_cmd(cmd):
    """Run a command on the remote server via SSH."""
    load_env()
    server_ip = env.get("SERVER_IP", "")
    if not server_ip:
        return {"ok": False, "output": "SERVER_IP not set in .env"}
    try:
        result = subprocess.run(
            ["ssh", f"root@{server_ip}", cmd],
            capture_output=True, text=True, timeout=15
        )
        return {"ok": result.returncode == 0, "output": result.stdout + result.stderr}
    except subprocess.TimeoutExpired:
        return {"ok": False, "output": "SSH timeout (15s)"}
    except Exception as e:
        return {"ok": False, "output": str(e)}


def http_get(url, timeout=5):
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return {"ok": True, "data": json.loads(resp.read())}
    except Exception as e:
        return {"ok": False, "data": None, "error": str(e)}


# ─────────────────────────────────────────────
# API HELPERS
# ─────────────────────────────────────────────

def api_request(method, url, data=None, headers=None):
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            code = resp.getcode()
            try:
                result = json.loads(resp.read())
            except Exception:
                result = None
            return {"ok": 200 <= code < 300, "code": code, "data": result}
    except urllib.error.HTTPError as e:
        return {"ok": False, "code": e.code, "data": None}
    except Exception as e:
        return {"ok": False, "code": 0, "data": None, "error": str(e)}


def twitch_headers():
    load_env()
    return {
        "Authorization": f"Bearer {env.get('TWITCH_ACCESS_TOKEN', '')}",
        "Client-Id": env.get("TWITCH_CLIENT_ID", ""),
    }


def kick_headers():
    load_env()
    return {
        "Authorization": f"Bearer {env.get('KICK_ACCESS_TOKEN', '')}",
    }


def refresh_twitch():
    load_env()
    rt = env.get("TWITCH_REFRESH_TOKEN", "")
    if not rt:
        return False
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": rt,
        "client_id": env.get("TWITCH_CLIENT_ID", ""),
        "client_secret": env.get("TWITCH_CLIENT_SECRET", ""),
    }).encode()
    req = urllib.request.Request("https://id.twitch.tv/oauth2/token", data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            if result.get("access_token"):
                save_env_value("TWITCH_ACCESS_TOKEN", result["access_token"])
                save_env_value("TWITCH_REFRESH_TOKEN", result.get("refresh_token", rt))
                return True
    except Exception:
        pass
    return False


def refresh_kick():
    load_env()
    rt = env.get("KICK_REFRESH_TOKEN", "")
    if not rt:
        return False
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": rt,
        "client_id": env.get("KICK_CLIENT_ID", ""),
        "client_secret": env.get("KICK_CLIENT_SECRET", ""),
    }).encode()
    req = urllib.request.Request("https://id.kick.com/oauth/token", data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            if result.get("access_token"):
                save_env_value("KICK_ACCESS_TOKEN", result["access_token"])
                save_env_value("KICK_REFRESH_TOKEN", result.get("refresh_token", rt))
                return True
    except Exception:
        pass
    return False


def twitch_api(method, url, data=None):
    result = api_request(method, url, data, twitch_headers())
    if result.get("code") == 401:
        if refresh_twitch():
            result = api_request(method, url, data, twitch_headers())
    return result


def kick_api(method, url, data=None):
    result = api_request(method, url, data, kick_headers())
    if result.get("code") == 401:
        if refresh_kick():
            result = api_request(method, url, data, kick_headers())
    return result


# ─────────────────────────────────────────────
# ROUTES
# ─────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("dashboard.html")


@app.route("/api/status")
def api_status():
    load_env()
    server_ip = env.get("SERVER_IP", "")
    if not server_ip:
        return jsonify({"ok": False, "error": "SERVER_IP not set"})

    # SRS API check
    srs = http_get(f"http://{server_ip}:1985/api/v1/summaries")

    # Docker containers
    docker = ssh_cmd("docker ps --format '{{.Names}}|{{.Status}}'")
    containers = {}
    if docker["ok"]:
        for line in docker["output"].strip().splitlines():
            if "|" in line:
                name, status = line.split("|", 1)
                containers[name] = status

    # Stunnel
    stunnel = ssh_cmd("systemctl is-active stunnel4")

    # Active streams
    streams = http_get(f"http://{server_ip}:1985/api/v1/streams/")

    return jsonify({
        "ok": True,
        "server_ip": server_ip,
        "srs_online": srs["ok"],
        "containers": containers,
        "stunnel": stunnel["output"].strip() if stunnel["ok"] else "unknown",
        "streams": streams.get("data", {}).get("streams", []) if streams["ok"] else [],
    })


@app.route("/api/logs")
def api_logs():
    result = ssh_cmd("docker logs --tail 50 multistream-srs 2>&1")
    return jsonify(result)


@app.route("/api/restart", methods=["POST"])
def api_restart():
    result = ssh_cmd("cd /opt/multistream && docker compose restart && systemctl restart stunnel4")
    return jsonify(result)


@app.route("/api/deploy", methods=["POST"])
def api_deploy():
    load_env()
    server_ip = env.get("SERVER_IP", "")
    twitch_key = env.get("TWITCH_STREAM_KEY", "")
    kick_key = env.get("KICK_STREAM_KEY", "")

    if not server_ip:
        return jsonify({"ok": False, "output": "SERVER_IP not set"})

    config_dir = Path(__file__).resolve().parent.parent / "config"

    # Build docker-compose with keys substituted
    compose_src = (config_dir / "docker-compose.yml").read_text()
    compose_src = compose_src.replace("TWITCH_STREAM_KEY", twitch_key)
    compose_src = compose_src.replace("KICK_STREAM_KEY", kick_key)
    compose_src = compose_src.replace("X_RTMP_URL", env.get("X_RTMP_URL", "X_RTMP_URL"))
    compose_src = compose_src.replace("X_STREAM_KEY", env.get("X_STREAM_KEY", "X_STREAM_KEY"))

    import tempfile
    errors = []

    # Upload docker-compose
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yml", delete=False) as f:
        f.write(compose_src)
        tmp_compose = f.name
    r = subprocess.run(["scp", tmp_compose, f"root@{server_ip}:/opt/multistream/docker-compose.yml"],
                       capture_output=True, text=True, timeout=15)
    os.unlink(tmp_compose)
    if r.returncode != 0:
        errors.append(f"docker-compose upload: {r.stderr}")

    # Upload srs.conf
    r = subprocess.run(["scp", str(config_dir / "srs.conf"), f"root@{server_ip}:/opt/multistream/conf/srs.conf"],
                       capture_output=True, text=True, timeout=15)
    if r.returncode != 0:
        errors.append(f"srs.conf upload: {r.stderr}")

    # Upload stunnel config
    r = subprocess.run(["scp", str(config_dir / "kick-stunnel.conf"), f"root@{server_ip}:/etc/stunnel/kick.conf"],
                       capture_output=True, text=True, timeout=15)
    if r.returncode != 0:
        errors.append(f"stunnel config upload: {r.stderr}")

    # Restart
    restart = ssh_cmd("cd /opt/multistream && docker compose up -d && systemctl restart stunnel4")

    if errors:
        return jsonify({"ok": False, "output": "\n".join(errors)})
    return jsonify(restart)


@app.route("/api/golive", methods=["POST"])
def api_golive():
    load_env()
    body = request.json or {}
    title = body.get("title", "").strip()
    game = body.get("game", "").strip()

    if not title and not game:
        return jsonify({"ok": False, "error": "Provide title, game, or both"})

    # Which platforms to update (default: all configured)
    platforms = body.get("platforms", ["twitch", "kick"])
    results = {}

    # Lookup game IDs
    twitch_game_id = None
    kick_category_id = None

    if game:
        encoded = urllib.parse.quote(game)

        if "twitch" in platforms:
            tr = twitch_api("GET", f"https://api.twitch.tv/helix/search/categories?query={encoded}")
            if tr["ok"] and tr["data"]:
                cats = tr["data"].get("data", [])
                for c in cats:
                    if c["name"].lower() == game.lower():
                        twitch_game_id = c["id"]
                        break
                if not twitch_game_id and cats:
                    twitch_game_id = cats[0]["id"]

        if "kick" in platforms:
            kr = kick_api("GET", f"https://api.kick.com/public/v1/categories?q={encoded}")
            if kr["ok"] and kr["data"]:
                cats = kr["data"].get("data", [])
                for c in cats:
                    if c["name"].lower() == game.lower():
                        kick_category_id = c["id"]
                        break
                if not kick_category_id and cats:
                    kick_category_id = cats[0]["id"]

    # Set Twitch
    if "twitch" in platforms:
        twitch_body = {}
        if title:
            twitch_body["title"] = title
        if twitch_game_id:
            twitch_body["game_id"] = str(twitch_game_id)
        if twitch_body:
            broadcaster_id = env.get("TWITCH_BROADCASTER_ID", "")
            tr = twitch_api("PATCH", f"https://api.twitch.tv/helix/channels?broadcaster_id={broadcaster_id}", twitch_body)
            results["twitch"] = "updated" if tr["ok"] else "failed"

    # Set Kick
    if "kick" in platforms:
        kick_body = {}
        if title:
            kick_body["stream_title"] = title
        if kick_category_id:
            kick_body["category_id"] = kick_category_id
        if kick_body:
            kr = kick_api("PATCH", "https://api.kick.com/public/v1/channels", kick_body)
            results["kick"] = "updated" if kr["ok"] else "failed"

    return jsonify({"ok": True, "results": results, "game_ids": {
        "twitch": twitch_game_id,
        "kick": kick_category_id,
    }})


@app.route("/api/title", methods=["POST"])
def api_title():
    body = request.json or {}
    title = body.get("title", "").strip()
    if not title:
        return jsonify({"ok": False, "error": "No title provided"})
    return api_golive_inner(title=title)


@app.route("/api/game", methods=["POST"])
def api_game():
    body = request.json or {}
    game = body.get("game", "").strip()
    if not game:
        return jsonify({"ok": False, "error": "No game provided"})
    return api_golive_inner(game=game)


def api_golive_inner(title="", game=""):
    """Shared logic for title/game/golive endpoints."""
    with app.test_request_context(json={"title": title, "game": game}):
        return api_golive()


@app.route("/api/config")
def api_config():
    """Return non-secret config info for the dashboard."""
    load_env()
    has_twitch_api = bool(env.get("TWITCH_ACCESS_TOKEN"))
    has_kick_api = bool(env.get("KICK_ACCESS_TOKEN"))
    return jsonify({
        "server_ip": env.get("SERVER_IP", ""),
        "has_twitch_key": bool(env.get("TWITCH_STREAM_KEY")),
        "has_kick_key": bool(env.get("KICK_STREAM_KEY")),
        "has_x_key": bool(env.get("X_STREAM_KEY")),
        "has_twitch_api": has_twitch_api,
        "has_kick_api": has_kick_api,
    })


if __name__ == "__main__":
    load_env()
    print("Multistreamer Dashboard: http://localhost:3000")
    app.run(host="127.0.0.1", port=3000, debug=False)
