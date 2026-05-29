#!/bin/bash
# =============================================================================
# Dev Container Egress Firewall
# =============================================================================
# Restricts outbound network traffic to only the domains Claude Code and
# your development tools need. Default-deny policy with explicit allowlist.
#
# Requires: NET_ADMIN and NET_RAW capabilities in devcontainer.json runArgs.
#
# Customize the ALLOWED_DOMAINS array for your project's needs (e.g., add
# your private registry, internal APIs, etc.)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Allowed domains (customize for your organization)
# ---------------------------------------------------------------------------
ALLOWED_DOMAINS=(
    # Claude Code API (required)
    "api.anthropic.com"

    # Telemetry (remove if CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1)
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"

    # Package registries (add/remove as needed)
    "registry.npmjs.org"
    # "pypi.org"
    # "files.pythonhosted.org"

    # VS Code marketplace (for extension installs)
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"

    # Add your internal domains below:
    # "artifactory.yourcompany.com"
    # "internal-api.yourcompany.com"
)

# ---------------------------------------------------------------------------
# Preserve Docker DNS before flushing
# ---------------------------------------------------------------------------
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

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
# Base rules: DNS, SSH, localhost
# ---------------------------------------------------------------------------
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ---------------------------------------------------------------------------
# Create ipset for allowed domains
# ---------------------------------------------------------------------------
ipset create allowed-domains hash:net

# ---------------------------------------------------------------------------
# Add GitHub IP ranges
# ---------------------------------------------------------------------------
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
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
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# ---------------------------------------------------------------------------
# Resolve and add allowed domains
# ---------------------------------------------------------------------------
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain (skipping)"
        continue
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        ipset add allowed-domains "$ip" 2>/dev/null || true
    done < <(echo "$ips")
done

# ---------------------------------------------------------------------------
# Allow host network (required for Docker communication)
# ---------------------------------------------------------------------------
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network: $HOST_NETWORK"
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

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

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "FAIL: Cannot reach api.github.com (should be allowed)"
    exit 1
else
    echo "PASS: api.github.com reachable as expected"
fi

echo "Firewall ready."
