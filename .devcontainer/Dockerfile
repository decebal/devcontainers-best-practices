# =============================================================================
# Dev Container + Claude Code: Hardened Dockerfile
# =============================================================================
# This Dockerfile creates a secure development environment with:
#   - Non-root user ("developer") with minimal privileges
#   - Claude Code installed at a pinned (or latest) version
#   - Bubblewrap for Claude Code's native sandboxing
#   - Firewall tooling for network egress restrictions
#   - Organization-managed settings baked into the image
#
# Security patterns sourced from:
#   - anthropics/claude-code (official reference)
#   - trailofbits/claude-code-devcontainer (bubblewrap, NPM hardening)
#   - FoamoftheSea/claude-code-sandbox (resource limits, cap-drop)
#   - centminmod/claude-code-devcontainers (multi-tool, git hooks)
#
# Customize the base image and tooling sections for your project's stack.
# =============================================================================

# ---------------------------------------------------------------------------
# Base image
# ---------------------------------------------------------------------------
# Choose a base that matches your project's runtime.
# Examples:
#   node:20            - Node.js projects
#   python:3.12        - Python projects
#   mcr.microsoft.com/devcontainers/base:ubuntu - general purpose
#
# For maximum reproducibility, pin by digest (trailofbits pattern):
#   FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04@sha256:<digest>
FROM node:20-slim

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
ARG TZ=UTC
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
# Core: git, sudo, shell
# Sandbox: bubblewrap (bwrap) — used by Claude Code's native sandboxing.
#   Installed following trailofbits/claude-code-devcontainer pattern.
# Firewall: iptables, ipset, iproute2, dnsutils, aggregate
# Optional: remove firewall packages if not using init-firewall.sh
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    sudo \
    zsh \
    curl \
    ca-certificates \
    less \
    procps \
    jq \
    # Bubblewrap for Claude Code native sandboxing (trailofbits pattern)
    bubblewrap \
    # Firewall tooling (remove if not needed)
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Non-root user
# ---------------------------------------------------------------------------
# Create a dedicated non-root user. Claude Code rejects
# --dangerously-skip-permissions when run as root.
#
# Sudoers: restrict to only the firewall script (least-privilege).
# The broad NOPASSWD:ALL line below is a convenience default — for
# production, replace it with scoped rules like the firewall sudoer.
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/zsh $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# ---------------------------------------------------------------------------
# Directories and permissions
# ---------------------------------------------------------------------------
RUN mkdir -p /workspace /home/$USERNAME/.claude /commandhistory \
    && chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude /commandhistory

# ---------------------------------------------------------------------------
# Organization-managed settings (HIGHEST PRECEDENCE)
# ---------------------------------------------------------------------------
# Values in this file override ALL user and project settings.
# See: https://code.claude.com/docs/en/settings#settings-files
#
# NOTE: Because this Dockerfile lives in the repo, engineers with write
# access can modify it. For truly tamper-proof policy, deliver settings
# via server-managed settings or MDM instead.
RUN mkdir -p /etc/claude-code
COPY managed-settings.json /etc/claude-code/managed-settings.json

# ---------------------------------------------------------------------------
# Install Claude Code
# ---------------------------------------------------------------------------
# Install globally so it's available to all users in the container.
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# ---------------------------------------------------------------------------
# Firewall script
# ---------------------------------------------------------------------------
# Copy and configure the egress restriction script.
# Remove this section if you rely on external network controls.
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh \
    && echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/$USERNAME-firewall \
    && chmod 0440 /etc/sudoers.d/$USERNAME-firewall

# ---------------------------------------------------------------------------
# Persist bash/zsh history
# ---------------------------------------------------------------------------
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && echo "$SNIPPET" >> /home/$USERNAME/.zshrc \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME /commandhistory

# ---------------------------------------------------------------------------
# Final setup
# ---------------------------------------------------------------------------
ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh

WORKDIR /workspace
USER $USERNAME
