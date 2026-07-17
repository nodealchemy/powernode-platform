#!/usr/bin/env bash
# Provisions per-run E2E test logins ONCE and shares them via E2E_LOGINS with
# every cypress-split worker process, then runs cypress-split with the given
# args (e.g. --split 4).
#
# Without this wrapper, each cypress-split worker's setupNodeEvents calls
# provisionTestLogins() independently (see frontend/cypress.config.ts), and
# since resetting a user's password invalidates any password a sibling worker
# already cached, the workers race and later resets 401 earlier ones. Setting
# E2E_LOGINS here short-circuits provisionTestLogins() in every worker (see
# scripts/e2e/provision-test-logins.cjs) so they all share one set of logins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "${SCRIPT_DIR}/../../frontend" && pwd)"

export E2E_LOGINS
E2E_LOGINS="$(node "${SCRIPT_DIR}/provision-test-logins.cjs")"

cd "${FRONTEND_DIR}"
exec npx cypress-split "$@"
