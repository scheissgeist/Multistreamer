#!/bin/bash
# Stream health monitor
# Checks SRS + Stunnel health, auto-restarts if down
# Run manually or via cron/task scheduler

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
LOG_FILE="$SCRIPT_DIR/../logs/monitor.log"

mkdir -p "$(dirname "$LOG_FILE")"

source "$ENV_FILE"
SSH="ssh root@$SERVER_IP"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check SRS API
SRS_OK=false
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:1985/api/v1/summaries" --connect-timeout 5 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    SRS_OK=true
fi

# Check stunnel via SSH
STUNNEL_OK=false
STUNNEL_STATUS=$($SSH "systemctl is-active stunnel4" 2>/dev/null)
if [ "$STUNNEL_STATUS" = "active" ]; then
    STUNNEL_OK=true
fi

# Report and fix
if $SRS_OK && $STUNNEL_OK; then
    log "OK: SRS + Stunnel healthy"
    exit 0
fi

if ! $SRS_OK; then
    log "WARN: SRS not responding (HTTP $HTTP_CODE). Restarting..."
    $SSH "cd /opt/multistream && docker compose restart" 2>&1 | while read line; do log "  $line"; done
    sleep 3
    RECHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP:1985/api/v1/summaries" --connect-timeout 5 2>/dev/null)
    if [ "$RECHECK" = "200" ]; then
        log "OK: SRS recovered after restart"
    else
        log "ERROR: SRS still down after restart (HTTP $RECHECK)"
    fi
fi

if ! $STUNNEL_OK; then
    log "WARN: Stunnel not active ($STUNNEL_STATUS). Restarting..."
    $SSH "systemctl restart stunnel4" 2>&1 | while read line; do log "  $line"; done
    sleep 2
    RECHECK=$($SSH "systemctl is-active stunnel4" 2>/dev/null)
    if [ "$RECHECK" = "active" ]; then
        log "OK: Stunnel recovered after restart"
    else
        log "ERROR: Stunnel still down after restart ($RECHECK)"
    fi
fi
