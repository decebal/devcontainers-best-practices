#!/bin/bash
set -euo pipefail
# Scoped wrapper: fix ownership of Docker-volume mount points.
# Docker volumes are created as root; the non-root user needs ownership.
chown developer:developer /workspace/node_modules
chown developer:developer /home/developer/.bun
