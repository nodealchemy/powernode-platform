#!/bin/bash
# reload-backend.sh — Soft-restart Puma via SIGUSR2 (hot restart: re-exec +
# re-preload from the current working tree).
#
# Used by the Claude Code Stop hook (.claude/hooks/service-restart-apply.sh)
# and available for manual mid-turn reloads:
#   bash scripts/reload-backend.sh
#
# No bootsnap clearing: bootsnap invalidates entries by file hash, so edited
# files recompile automatically on the next load — clearing the whole cache
# would only slow every reload. (An earlier version cleared a cache path from
# the pre-migration working tree; it had been a no-op since the move.)

set -euo pipefail

# User-scope units (dev-cell: installer --user) take precedence; system scope
# (dev box) is the fallback.
if systemctl --user cat powernode-backend@default.service &>/dev/null; then
    systemctl --user reload powernode-backend@default
else
    sudo systemctl reload powernode-backend@default
fi
