#!/usr/bin/env bash
#
# CI gate: fail if core re-introduces hardcoded private-extension coupling.
#
# Core integrates with extensions ONLY through generic, slug-agnostic seams
# (Powernode::ExtensionRegistry capabilities/providers, model decorators,
# ActiveSupport::Notifications, the frontend featureRegistry, and extension.json
# metadata) — it never names a specific extension slug. This guard bans the exact
# coupling patterns the decoupling sweep removed so they can't silently come back.
#
# Scope note: this checks for SPECIFIC coupling patterns, not every occurrence of the
# word "business"/"trading" — benign tier/plan names, domain terms, and the
# (out-of-scope, pre-existing) core trading MCP-tool surface are intentionally NOT
# flagged. See docs/contributing/core-extension-decoupling.md.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail=0
report() {
  echo "❌ $1"
  echo "$2" | sed 's/^/     /'
  echo ""
  fail=1
}

# --- Backend (server/): business-extension coupling that was removed from core. ---------
backend_paths=(server/app server/lib server/config)
declare -A backend_patterns=(
  ['business_loaded?']='business_loaded\?'
  ['business_enabled?']='business_enabled\?'
  ['billing_enabled?']='billing_enabled\?'
  ['loaded?("business")']='loaded\?\(["'\'']business["'\'']\)'
  [':business_mode']=':business_mode'
  ['PowernodeBusiness::']='PowernodeBusiness'
  ['BusinessAware']='BusinessAware'
)
for label in "${!backend_patterns[@]}"; do
  hits=$(grep -rnE "${backend_patterns[$label]}" "${backend_paths[@]}" 2>/dev/null)
  [ -n "$hits" ] && report "Core backend names the business extension ($label):" "$hits"
done

# --- Frontend (frontend/src): hardcoded extension-slug gates. Extensions self-register
#     nav/routes via featureRegistry; nav visibility is driven by loadedExtensions, not
#     by build-time slug literals in core. -----------------------------------------------
declare -A frontend_patterns=(
  ["extensionSlug: 'business'"]="extensionSlug:[[:space:]]*['\"]business['\"]"
  ["__EXTENSIONS__.includes('business')"]="__EXTENSIONS__\.includes\(['\"]business['\"]\)"
  ["__EXTENSIONS__.includes('trading')"]="__EXTENSIONS__\.includes\(['\"]trading['\"]\)"
)
if [ -d frontend/src ]; then
  for label in "${!frontend_patterns[@]}"; do
    hits=$(grep -rnE "${frontend_patterns[$label]}" frontend/src 2>/dev/null)
    [ -n "$hits" ] && report "Core frontend hardcodes an extension slug ($label):" "$hits"
  done
fi

if [ "$fail" -ne 0 ]; then
  echo "Core must not name a private extension. Route through generic seams instead:"
  echo "  backend  → FeatureGateService.capability_present?(:cap) / ExtensionRegistry.provider(:key),"
  echo "             model decorators, ActiveSupport::Notifications"
  echo "  frontend → featureRegistry.registerRoutes/registerNavItems; declare in extension.json"
  exit 1
fi

echo "✅ No hardcoded private-extension coupling in core."
exit 0
