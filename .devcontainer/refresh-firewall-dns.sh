#!/bin/bash
# =============================================================================
# Firewall DNS Refresher
# =============================================================================
# Periodically re-resolves allowed domains and updates the ipset.
# Solves CDN IP rotation problem: Anthropic, Sentry, etc. use CDNs whose
# IPs change frequently. A one-shot resolve at container start goes stale.
#
# Called by init-firewall.sh in two modes:
#   1. One-shot: resolve all domains once (during initial firewall setup)
#   2. Loop:     run as background daemon, refreshing every REFRESH_INTERVAL
#
# Usage:
#   refresh-firewall-dns.sh once      # resolve once and exit
#   refresh-firewall-dns.sh loop      # resolve in a loop (background daemon)
# =============================================================================

set -euo pipefail

IPSET_NAME="allowed-domains"
ENTRY_TIMEOUT=600          # ipset entry TTL in seconds (10 minutes)
REFRESH_INTERVAL=240       # seconds between refreshes (4 minutes)
PID_FILE="/tmp/refresh-firewall-dns.pid"

# ---------------------------------------------------------------------------
# Domain list (must match init-firewall.sh ALLOWED_DOMAINS)
# Sourced from a shared config to keep them in sync.
# ---------------------------------------------------------------------------
DOMAINS_FILE="/usr/local/etc/firewall-allowed-domains.conf"

if [ ! -f "$DOMAINS_FILE" ]; then
    echo "ERROR: $DOMAINS_FILE not found"
    exit 1
fi

# Read domains from config file (one per line, # comments allowed)
mapfile -t ALLOWED_DOMAINS < <(grep -v '^\s*#' "$DOMAINS_FILE" | grep -v '^\s*$')

# ---------------------------------------------------------------------------
# Resolve and update ipset
# ---------------------------------------------------------------------------
resolve_all() {
    local failures=0

    for domain in "${ALLOWED_DOMAINS[@]}"; do
        ips=$(dig +noall +answer +tries=2 +timeout=3 A "$domain" | awk '$4 == "A" {print $5}')
        if [ -z "$ips" ]; then
            echo "WARNING: Failed to resolve $domain"
            ((failures++)) || true
            continue
        fi

        while read -r ip; do
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                ipset add -exist "$IPSET_NAME" "$ip" timeout "$ENTRY_TIMEOUT" 2>/dev/null || true
            fi
        done <<< "$ips"
    done

    if [ "$failures" -gt 0 ]; then
        echo "WARNING: $failures domain(s) failed to resolve"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
MODE="${1:-once}"

case "$MODE" in
    once)
        resolve_all
        ;;
    loop)
        # Write PID for clean shutdown
        echo $$ > "$PID_FILE"
        trap 'rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT

        echo "DNS refresh daemon started (PID $$, interval ${REFRESH_INTERVAL}s)"
        while true; do
            sleep "$REFRESH_INTERVAL"
            resolve_all
        done
        ;;
    *)
        echo "Usage: $0 {once|loop}"
        exit 1
        ;;
esac
