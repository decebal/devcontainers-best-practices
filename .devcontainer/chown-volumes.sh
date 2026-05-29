#!/bin/bash
set -euo pipefail
# Scoped wrapper: fix ownership of Docker-volume mount points.
# Docker volumes are created as root; the non-root user needs ownership.
#
# Validates paths are actual mount points before chown to prevent
# operating on the underlying container filesystem if a volume mount
# failed silently.

for path in /workspace/node_modules /home/developer/.bun; do
    if mountpoint -q "$path" 2>/dev/null; then
        chown developer:developer "$path"
        echo "Fixed ownership: $path"
    else
        echo "WARNING: $path is not a mount point (skipping)"
    fi
done
