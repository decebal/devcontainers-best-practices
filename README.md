# Dev Containers + Claude Code: Best Practices Template

A hardened, production-ready dev container template that gives your team:

- **Consistent environments** -- one source of truth committed in Git
- **Claude Code best practices** -- pre-configured, version-pinned, org-policy enforced
- **Security isolation** -- non-root user, filesystem sandboxing, network egress firewall
- **Instant adoption** -- `git clone` + "Reopen in Container" = done

## Quick start

1. Copy the `.devcontainer/` folder into your project repository
2. Adjust the `Dockerfile` base image for your stack (Node, Python, etc.)
3. Edit `managed-settings.json` for your organization's policy
4. Customize `init-firewall.sh` with your internal domains
5. Open in VS Code/Cursor and click **"Reopen in Container"**

## What's included

```
.devcontainer/
  devcontainer.json       # Container config: mounts, env vars, security settings
  Dockerfile              # Hardened image with Claude Code + non-root user
  managed-settings.json   # Org policy (highest precedence, overrides user settings)
  init-firewall.sh        # Default-deny egress firewall with domain allowlist
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
|   ~/.ssh (NOT mounted)|          |   Non-root user: "developer"    |
|   ~/.aws (NOT mounted)|          |   Egress firewall: default-deny |
|                       |          |   Managed settings: enforced    |
+-----------------------+          +----------------------------------+
```

## Security layers

| Layer | What it does |
|-------|-------------|
| **Non-root user** | Claude Code runs as `developer`, not `root`. Prevents container-escape and rejects `--dangerously-skip-permissions` if accidentally run as root. |
| **Filesystem sandboxing** | Only `/workspace` (your project) is bind-mounted. Claude cannot modify host system files, other projects, or home directory configs. |
| **Network egress firewall** | Default-deny iptables policy. Only `api.anthropic.com`, GitHub, and your configured domains are reachable. Prevents data exfiltration. |
| **Managed settings** | `/etc/claude-code/managed-settings.json` enforces org policy at highest precedence. Engineers cannot override these settings. |
| **No host secrets** | `~/.ssh`, `~/.aws`, cloud credentials are NOT mounted. Use SSH agent forwarding or repo-scoped tokens instead. |

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
            "Bash(rm -rf *)"
        ]
    }
}
```

### Skip the firewall

If you use external network controls, remove from `devcontainer.json`:
- `runArgs` (NET_ADMIN, NET_RAW capabilities)
- `postStartCommand`
- `waitFor`

And remove `init-firewall.sh` and firewall packages from the `Dockerfile`.

## Using the Dev Container Feature instead

For a simpler setup without the Dockerfile, you can use the official Claude Code Dev Container Feature:

```json
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
    }
}
```

This installs Claude Code automatically but does not include the firewall, managed settings, or other hardening from this template.

## Resources

- [Claude Code Dev Containers docs](https://code.claude.com/docs/en/devcontainer)
- [Dev Containers specification](https://containers.dev/)
- [Claude Code admin setup](https://code.claude.com/docs/en/admin-setup)
- [Network access requirements](https://code.claude.com/docs/en/network-config#network-access-requirements)
- [Managed settings reference](https://code.claude.com/docs/en/settings#settings-files)
