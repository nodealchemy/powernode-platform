#!/bin/bash
#
# check-authz-coverage.sh — Missing-authorization regression guard
# =============================================================================
# Flags the systemic pattern behind a wave of privilege bugs: a user-facing
# api/v1 controller shipped with ONLY account-scoping (set_*/current_account)
# and NO authorization check, so ANY authenticated tenant user could invoke a
# state-changing / sensitive action (governance plane, kubeconfig export, swarm
# secrets, etc.). The fix is a per-action permission gate:
#
#     require_permission("devops.swarm.secrets.read")   # ← in the action
#     include ::Ai::GatedActions                        # ← autonomy gate
#     before_action :authorize_devops!                  # ← before_action gate
#
# SCOPE
#   server/app/controllers/api/v1/**/*.rb            — core, user-facing, JWT/user-authed.
#   extensions/*/server/app/controllers/api/v1/**/*.rb — every extension's user-facing
#            api/v1 tree (system, marketing, supply-chain). Private extensions
#            (extensions/private/*) are NOT scanned — they live outside this glob
#            and never enter the public baseline.
#   EXCLUDES api/v1/internal/**, api/v1/worker/**, and — in extension trees —
#            **/node_api/**, **/worker_api/**, **/federation_api/**: all
#            service/peer-token authed (no tenant user context; authz handled at
#            the token boundary).
#
# HEURISTIC (high-signal, low-noise — catches the WORST "zero-authz controller"
# case in preference to per-action precision):
#   A controller is FLAGGED when ALL of the following hold:
#     (a) it lives under api/v1 (excluding internal/** and worker/**), AND
#     (b) it contains NO authorization token ANYWHERE in the file — none of:
#           require_permission   require_any_permission   authorize_action
#           has_permission?      Ai::GatedActions / GatedActions / AutonomyGate
#           before_action :authorize…   (an explicit authorize* before_action)
#         — i.e. it is NOT "authz-bearing", AND
#     (c) it defines at least one action method BEYOND {index, show, new, edit}
#         (a likely write/custom action — `def <name>` where <name> is not one
#         of the four read-only RESTful readers). This approximates "has a
#         state-changing / POST/PUT/PATCH/DELETE-exposed action" without a
#         precise routes.rb verb mapping.
#     AND it is NOT EXEMPT (see below).
#
# EXEMPT (by design — token/public/callback flows, never tenant-write authz):
#   A controller is exempt if EITHER:
#     • its relpath matches a name in the EXEMPT_NAMES list below (oauth
#       callbacks, health, status, public pages, streamable_http,
#       approval_tokens, ralph_loop_webhooks, csrf, auth flows, webhooks …), OR
#     • it carries an inline class-level annotation  `# authz-ok: <reason>`
#       (the ergonomic, self-documenting opt-out for NEW vetted cases).
#
# BASELINE (avoid alert fatigue):
#   scripts/authz-coverage-allowlist.txt holds the CURRENT flagged relpaths that
#   are vetted-acceptable (read-only dashboards, public/token flows, already
#   account-scoped writes deemed acceptable at baseline time). The guard is
#   GREEN over the existing tree and FAILS only on a NEW, unlisted, unannotated
#   zero-authz controller. Keyed by relpath (a controller either has authz or it
#   does not — content-hashing would add no signal here).
#
#   Two complementary opt-outs, mirroring check-account-scoping.sh:
#     (a) inline `# authz-ok: <reason>` — preferred for new intentional cases;
#     (b) the allowlist file — seeds the green baseline without touching files.
#
# REGENERATE BASELINE (only after reviewing every current flagged controller):
#       bash scripts/check-authz-coverage.sh --update-allowlist
#
# KNOWN LIMITATION
#   This is a per-CONTROLLER guard, not per-action. It catches the "zero-authz
#   controller with writes" case. It does NOT catch a per-action gap inside an
#   otherwise-gated controller (e.g. nine gated actions + one ungated `def
#   purge`) — the file is authz-bearing, so it passes. Per-action coverage needs
#   a routes-verb mapping and is out of scope here.
#
# EXIT CODES
#   0  no new/unbaselined flagged controllers (CI-green; vetted set allowed)
#   1  one or more NEW zero-authz controllers (CI gate trips on regressions only)
#
# Advisory-friendly: pass --warn to always exit 0 (report-only mode).
# =============================================================================

set -uo pipefail

# --- Locate repo root so the script works from any CWD ----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CONTROLLERS_DIR="server/app/controllers/api/v1"
ALLOWLIST="scripts/authz-coverage-allowlist.txt"

# Color codes (match pattern-validation.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="check"   # check | update
WARN_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --update-allowlist) MODE="update" ;;
        --warn)             WARN_ONLY=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# --- Authorization tokens (any one makes a controller "authz-bearing") -------
# Note: `authorize_action` (not bare `authorize`) — the bare word collides with
# `def authorize` oauth action names and route comments. `before_action ...
# :authorize…` is matched separately so a real authorize* before_action counts.
#
# `require_[a-z_]+_permission` is a generic family token covering the per-area
# permission gates used across BOTH core and the extension trees:
#   require_read_permission / require_write_permission / require_admin_permission
#   require_signing_keys_permission (supply-chain) / require_system_permission
#   require_webhook_permission / require_devops_permission / require_execute_permission …
# Each such helper wraps current_user.has_permission?(…) and renders 403. This is
# purely ADDITIVE (it can only make MORE controllers authz-bearing).
#
# `require_admin_access` is the consolidated admin gate in the Authentication
# concern — `require_admin_access(*also_allow)` ⇒ `require_any_permission(
# "admin.access", *also_allow)`. It is a real authz gate, so controllers using it
# (e.g. admin/proxy_settings, site_settings) ARE authz-bearing. Matched literally:
# it is the only `require_*_access` helper in the tree and the name is precise.
AUTHZ_RE='require_permission|require_any_permission|require_[a-z_]+_permission|require_admin_access|authorize_action|has_permission\?|Ai::GatedActions|::GatedActions|GatedActions|AutonomyGate|before_action[^#]*:authorize'

# --- Exempt-by-name list (token/public/callback flows) -----------------------
# Matched as a substring of the relpath under server/app/controllers/. These are
# the spec-vetted public/token/callback shapes that never carry tenant-write
# authz. Kept explicit (not derived) so the exemption is auditable.
EXEMPT_NAMES=(
    "api/v1/oauth/"                                  # oauth app/registration callbacks
    "api/v1/mcp_oauth_controller.rb"                 # mcp oauth authorize/callback
    "api/v1/health_controller.rb"                    # health probe
    "api/v1/public/status_controller.rb"             # public status page
    "api/v1/public/"                                  # public pages
    "api/v1/version_controller.rb"                   # version banner
    "api/v1/config_controller.rb"                     # bootstrap config (allowed_hosts)
    "api/v1/csrf_controller.rb"                       # csrf token mint
    "api/v1/setup_controller.rb"                      # first-run setup (token-gated)
    "api/v1/mcp/streamable_http_controller.rb"        # MCP streamable HTTP transport
    "api/v1/devops/approval_tokens_controller.rb"     # signed approval-token flow
    "api/v1/ai/ralph_loop_webhooks_controller.rb"     # ralph loop webhook receiver
    "api/v1/webhooks/"                                # inbound webhook receivers
    "api/v1/chat/webhooks_controller.rb"              # chat webhook receiver
    "api/v1/auth/"                                     # login/register/password/2fa flows
    "api/v1/worker_auth_controller.rb"                # worker auth handshake (token)
    "api/v1/test_controller.rb"                       # test-env only helper
    "api/v1/worker_test_controller.rb"               # test-env only helper
    # --- Extension trees (matched as a substring of the full repo-relative key) -
    "api/v1/system/webhooks/"                         # system ext: nested inbound HMAC webhook receivers
    "system/sdwan/bootstrap_controller.rb"           # system ext: signed-token device bootstrap (the token IS the auth)
    "system/module_publications_controller.rb"       # system ext: CI-worker Bearer-token authed (Worker.authenticate)
    "marketing/public/"                               # marketing ext: public, unauthenticated pages (skip_before_action :authenticate_request)
    "supply_chain/licenses_controller.rb"            # supply-chain ext: public, read-only SPDX license reference catalog (skip auth; global reference data, no tenant state/mutation)
)

# Is this relpath exempt by name?
is_exempt_name() {
    local rel="$1" name
    for name in "${EXEMPT_NAMES[@]}"; do
        case "$rel" in
            *"$name"*) return 0 ;;
        esac
    done
    return 1
}

# --- Core classification -----------------------------------------------------
# A controller is "flagged" (zero-authz with a likely write action) when it is
# NOT authz-bearing, NOT exempt, NOT annotated, and defines an action method
# beyond {index, show, new, edit}.
#
# Emits, one per line, the relpath KEY of every CURRENTLY-flagged controller —
# BEFORE allowlist filtering. The first non-RESTful action name is appended after
# a TAB for the human-readable report.
#
# SCAN TREES (core + every extension's api/v1 tree). Each tree is "ROOT|STRIP":
#   • core       ROOT=server/app/controllers/api/v1, STRIP=server/app/controllers/
#                → key = "api/v1/…" (UNCHANGED — existing allowlist entries match).
#   • extensions ROOT=extensions/<ext>/server/app/controllers/api/v1, STRIP=""
#                → key = the FULL repo-relative path, e.g.
#                  "extensions/system/server/app/controllers/api/v1/system/foo.rb".
#                  The full path guarantees key UNIQUENESS so an extension's
#                  api/v1/system/… never collides with core's api/v1/system/… in
#                  the allowlist or report. (Private extensions live at
#                  extensions/private/*/server/… and are intentionally NOT matched
#                  by the extensions/*/… glob — they stay out of the public baseline.)
scan_trees() {
    printf '%s\n' "${CONTROLLERS_DIR}|server/app/controllers/"
    local d
    for d in extensions/*/server/app/controllers/api/v1; do
        [[ -d "$d" ]] || continue
        printf '%s\n' "${d}|"
    done
}

flagged_controllers() {
    local spec root strip
    while IFS= read -r spec; do
        root="${spec%%|*}"
        strip="${spec#*|}"
        find "${root}" -name '*.rb' -type f 2>/dev/null | sort | while IFS= read -r f; do
            # Exclude service-token-authed trees (no tenant-user context; authz is
            # enforced at the token boundary). Core: internal/, worker/. Extensions
            # additionally: node_api/, worker_api/ (service tokens) and
            # federation_api/ (federation-peer token, authenticate_federation_peer).
            case "$f" in
                */api/v1/internal/*)  continue ;;
                */api/v1/worker/*)    continue ;;
                */node_api/*)         continue ;;
                */worker_api/*)       continue ;;
                */federation_api/*)   continue ;;
            esac

            rel="${f#"$strip"}"

            # (b) authz-bearing? -> not flagged.
            if grep -qE "${AUTHZ_RE}" "$f" 2>/dev/null; then
                continue
            fi

            # exempt by inline class-level annotation
            if grep -qE '#\s*authz-ok:' "$f" 2>/dev/null; then
                continue
            fi

            # exempt by name (token/public/callback)
            if is_exempt_name "$rel"; then
                continue
            fi

            # (c) has an action method beyond index/show/new/edit?
            first_action="$(grep -oP '^\s*def\s+\K[a-z_][a-zA-Z0-9_]*' "$f" 2>/dev/null \
                | grep -vxE 'index|show|new|edit' | head -1)"
            [[ -z "$first_action" ]] && continue

            printf '%s\t%s\n' "$rel" "$first_action"
        done
    done < <(scan_trees)
}

# --- Update mode: regenerate the allowlist from the current tree -------------
if [[ "$MODE" == "update" ]]; then
    {
        echo "# Authorization-coverage guard — baseline allowlist"
        echo "# Format: <relpath under server/app/controllers/>"
        echo "# Generated by: scripts/check-authz-coverage.sh --update-allowlist"
        echo "# The CURRENT vetted-acceptable zero-authz controllers (read-only"
        echo "# dashboards, public/token flows, account-scoped writes acceptable at"
        echo "# baseline). New flagged controllers must add authz, an inline"
        echo "# '# authz-ok: <reason>' annotation, or — if vetted — be added here."
        flagged_controllers | cut -f1 | sort -u
    } > "${ALLOWLIST}"
    n=$(grep -cvE '^\s*(#|$)' "${ALLOWLIST}")
    echo -e "${GREEN}Wrote ${ALLOWLIST} with ${n} baselined controllers.${NC}"
    exit 0
fi

# --- Check mode --------------------------------------------------------------
declare -A ALLOWED=()
if [[ -f "${ALLOWLIST}" ]]; then
    while IFS= read -r entry; do
        [[ "$entry" =~ ^[[:space:]]*(#|$) ]] && continue
        ALLOWED["$entry"]=1
    done < "${ALLOWLIST}"
fi

new_hits=0
baselined=0

echo -e "${BLUE}=== Missing-authorization coverage guard ===${NC}"
echo "Scanning core + extension api/v1 controllers"
echo "  (excluding internal/, worker/, node_api/, worker_api/, federation_api/)"
echo ""

while IFS=$'\t' read -r rel action; do
    [[ -z "$rel" ]] && continue
    if [[ -n "${ALLOWED[$rel]:-}" ]]; then
        baselined=$((baselined + 1))
        continue
    fi
    new_hits=$((new_hits + 1))
    echo -e "${RED}✗ ${rel}${NC}"
    echo "    state-changing/custom action with NO authorization: def ${action}"
    echo -e "    ${YELLOW}↳ add require_permission(\"…\") / a gate, annotate \`# authz-ok: <reason>\`, or --update-allowlist${NC}"
    echo ""
done < <(flagged_controllers)

echo -e "${BLUE}--- Summary ---${NC}"
echo "Baselined (vetted) zero-authz controllers skipped: ${baselined}"
if [[ "$new_hits" -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS — no new zero-authz controllers.${NC}"
    exit 0
fi

echo -e "${RED}✗ FAIL — ${new_hits} new zero-authz controller(s) with state-changing actions.${NC}"
echo "  Add a permission gate (require_permission / GatedActions / authorize*),"
echo "  or — if a vetted public/token flow — add '# authz-ok: <reason>' or run --update-allowlist."
if [[ "$WARN_ONLY" -eq 1 ]]; then
    echo -e "${YELLOW}(--warn: reporting only, exiting 0)${NC}"
    exit 0
fi
exit 1
