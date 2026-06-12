# =============================================================================
# Dev Container + Claude Code: Hardened Dockerfile
# =============================================================================
# This Dockerfile creates a secure development environment with:
#   - Non-root user ("developer") with minimal privileges
#   - Bun runtime for fast JavaScript/TypeScript tooling
#   - Claude Code installed via bun
#   - Bubblewrap for Claude Code's native sandboxing
#   - Firewall tooling for network egress restrictions
#   - Organization-managed settings baked into the image
#
# Security patterns sourced from:
#   - anthropics/claude-code (official reference)
#   - trailofbits/claude-code-devcontainer (bubblewrap, supply chain hardening)
#   - FoamoftheSea/claude-code-sandbox (resource limits, cap-drop)
#   - centminmod/claude-code-devcontainers (multi-tool, git hooks)
#
# Customize the base image and tooling sections for your project's stack.
# =============================================================================

# ---------------------------------------------------------------------------
# Base image
# ---------------------------------------------------------------------------
# Using Debian slim as the base — bun is installed separately.
# For maximum reproducibility, pin by digest (trailofbits pattern):
#   FROM debian:bookworm-slim@sha256:<digest>
FROM debian:bookworm-slim

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
ARG TZ=UTC
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000
ARG BUN_VERSION=1.2.15

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
    wget \
    ca-certificates \
    less \
    procps \
    jq \
    fzf \
    man-db \
    unzip \
    gnupg2 \
    gh \
    nano \
    vim \
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
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/zsh $USERNAME

# ---------------------------------------------------------------------------
# Directories and permissions
# ---------------------------------------------------------------------------
# Pre-create the named-volume mount points (node_modules, .bun) owned by the
# non-root user. When a named volume is empty, Docker copies the image
# directory's owner into it on first mount, so these volumes come up writable
# with NO runtime chown / sudo needed. See devcontainer.json "mounts".
RUN mkdir -p /workspace /workspace/node_modules \
        /home/$USERNAME/.claude /home/$USERNAME/.bun /commandhistory \
    && chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude \
        /home/$USERNAME/.bun /commandhistory

# ---------------------------------------------------------------------------
# Install Bun
# ---------------------------------------------------------------------------
# Install bun to /usr/local (system-wide) so the Docker volume mounted at
# ~/.bun (for cache/globals persistence) doesn't clobber the binary.
# See: https://github.com/decebal/devcontainers-best-practices/issues/2
ENV BUN_INSTALL=/usr/local
ENV PATH=/usr/local/bin:$PATH

RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v${BUN_VERSION}"

# Create ~/.bun for cache/global packages (volume-mounted in devcontainer.json)
RUN mkdir -p /home/$USERNAME/.bun && chown $USERNAME:$USERNAME /home/$USERNAME/.bun

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
# git-delta (better diffs)
# ---------------------------------------------------------------------------
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
    wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# ---------------------------------------------------------------------------
# Switch to non-root user for remaining setup
# ---------------------------------------------------------------------------
USER $USERNAME

# ---------------------------------------------------------------------------
# zsh with Powerlevel10k theme
# ---------------------------------------------------------------------------
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x

# ---------------------------------------------------------------------------
# Install Claude Code
# ---------------------------------------------------------------------------
# Install globally via bun to /usr/local so it's available system-wide.
# Runs as root because BUN_INSTALL=/usr/local requires write to /usr/local/bin.
USER root
RUN bun install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
USER $USERNAME

# ---------------------------------------------------------------------------
# Startup scripts + scoped sudoers (least-privilege)
# ---------------------------------------------------------------------------
# Only the firewall script may run as root — and nothing else. This is far
# more secure than a broad NOPASSWD:ALL. Volume ownership is handled at build
# time (see the mount-point pre-creation above), so no privileged chown runs.
COPY init-firewall.sh refresh-firewall-dns.sh /usr/local/bin/
COPY firewall-allowed-domains.conf /usr/local/etc/firewall-allowed-domains.conf
USER root
# Use explicit 0755/0644 (not `chmod +x`): the build-context sources are
# group-writable (0664), and `chmod +x` would yield 0775 — leaving a
# NOPASSWD-sudo target group-writable. Lock these down so only root can edit
# the scripts that run as root.
RUN chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/refresh-firewall-dns.sh \
    && chmod 0644 /usr/local/etc/firewall-allowed-domains.conf \
    && echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

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

WORKDIR /workspace
USER $USERNAME
