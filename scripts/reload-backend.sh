#!/bin/bash
# reload-backend.sh — Clear bootsnap cache and soft-restart Puma via SIGUSR2.
#
# Used by the Claude Code Stop hook (.claude/hooks/service-restart-apply.sh)
# and available for manual mid-turn reloads:
#   bash scripts/reload-backend.sh
#
# Bootsnap clearing is required because SIGUSR2 re-execs Puma directly
# (bypasses the startup shell script), so extension bytecode can be stale.

set -euo pipefail

ISEQ_CACHE="/home/rett/Drive/Projects/powernode-platform/server/tmp/cache/bootsnap/compile-cache-iseq"

if [[ -d "$ISEQ_CACHE" ]]; then
  rm -rf "$ISEQ_CACHE"
fi

sudo systemctl reload powernode-backend@default
