# Core ↔ Extension Decoupling — audit & roadmap

**Goal:** no private-extension name (`business`, `trading`, …) is hardcoded anywhere
in core. Core integrates with extensions only through generic, slug-agnostic seams;
extension-specific behavior lives in the extension.

This is the plan of record for the de-hardcoding sweep. Status checkboxes track progress.

## Definitions (clarified)

- **Core mode** — the committed `server/Gemfile` + public-only `server/Gemfile.lock`.
  The Gemfile *discovers* extensions generically (`extensions_loader_helper.rb`
  scans `extensions/*/extension.json`) and bundles **all public** extensions
  (those in `.gitmodules`) regardless of whether they're enabled. Bundling ≠
  enabling — enablement is runtime (`config/extensions_state.json` + Flipper).
- **Private mode** (renamed from "full mode") — `server/Gemfile.private` (was
  `Gemfile.full`): core + public + **private** extensions (business, trading).
  Selected explicitly via `BUNDLE_GEMFILE=server/Gemfile.private bundle install`
  (sets `POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1`, re-evals the base Gemfile).
  Its lock `Gemfile.private.lock` is gitignored. Only for checkouts that actually
  have the private upstreams on disk.

## Generic seams core already provides (route everything through these)

- Backend: `Powernode::ExtensionRegistry` (`.loaded?(slug)`, `.slugs`,
  `.engine_for(slug)`, `.all`, `.feature_available?(feature, account:)`),
  `Shared::FeatureGateService` (`.extension_loaded?`, `.extension_enabled?`,
  `.extension_manifest_present?`, `.loaded_extensions`, `.core_mode?`),
  `Shared::ExtensionStateStore`, `Shared::ExtensionPaths`.
- Frontend: build-time `__EXTENSIONS__` slug list + `featureRegistry`
  (`isExtensionLoaded`, `registerRoutes`).

The gap: callers still name specific slugs (`business_loaded?`,
`includes('business')`) instead of being slug-driven, and several gates need the
extension to *register* a capability so core can ask generically.

## Phases

### Phase 0 — Rename `Gemfile.full` → `Gemfile.private`  ☐
Mechanical, contained. `server/Gemfile.full` → `Gemfile.private`;
`Gemfile.full.lock` → `Gemfile.private.lock` (regen); update
`/etc/powernode/backend-default.conf` `BUNDLE_GEMFILE`, `.gitignore`,
`extensions_loader_helper.rb` comment, `.gitea/workflows/extensions-bundle.yml`,
`scripts/check-lockfile-public-only.sh`, `scripts/regen-public-lockfile.sh`,
`docs/contributing/development-setup.md`, `docs/guides/extensions.md`,
`CLAUDE.md`, `CLAUDE.local.md`. Keep the `POWERNODE_INCLUDE_PRIVATE_EXTENSIONS` flag.

### Phase 1 — Generalize `FeatureGateService` (core-only) ☐
Remove the business-named methods; expose generic equivalents:
- `business_loaded?` → callers use `extension_loaded?(slug)`.
- `business_enabled?` → `extension_enabled?(slug)` (already generic; uses
  `:"#{slug}_mode"` Flipper).
- `set_business_enabled!(bool)` → `set_extension_enabled!(slug, bool)`.
- `business_feature?` / `core_feature?` → registry-driven: a feature is "core"
  iff no loaded extension claims it. Add `ExtensionRegistry.feature_owner(feature)`
  so `available?` needs no slug literal.
- `billing_enabled?` → `available?(:billing)` (registry decides which extension
  owns `:billing`).
- `development_info` → generic `{ extensions: loaded_extensions }` only.

### Phase 2 — Generic admin "Extensions" surface (FE + BE) ☐
Replace the business-specific Development tab + `PUT /admin_settings/development
{business_enabled}` with a generic per-slug toggle (`{slug, enabled}` →
`set_extension_enabled!`). Frontend lists `loaded_extensions` and toggles each;
per-extension detail (license/version/feature flags) is supplied **by the
extension** (registered via `featureRegistry`/an engine hook), not core. Removes
`business_installed`/`business_enabled` payload fields and the business copy.

### Phase 3 — Extension-provided presence-gate seams (core + submodules) ☐
The ~10 `loaded?("business")` / `:business_mode` gates in core
(`registrations_controller` public-registration gate, `subscription_channel`,
`config_controller` registration, `mcp_scanner_service`, `account_scoped`,
`agent_template`, `business_aware` concern, `flipper.rb` initializer) must become
capability-driven: the business extension **registers** the capability (e.g.
`public_registration`, `subscriptions`) and core checks
`available?(capability)` / iterates loaded extensions. **Requires business
submodule changes** (commit inside the submodule first).

### Phase 4 — Relocate extension logic out of core (submodules) ☐
- `worker_job_service.rb` trading market-arms/discovery logic → trading extension
  (pulled via a generic worker hook).
- `knowledge_doc_sync_service.rb` `EXTENSION_TAG_ROUTES` slug map → each extension
  declares the doc tags it owns (extension.json / registry), core queries generically.
- Audit `frontend` hardcoded `/app/business` and `/app/trading` routes + nav
  `extensionSlug` entries → register routes/nav from the extension via
  `featureRegistry` instead of core `navigation.tsx`.

### Phase 5 — Verify & guard ☐
rubocop + rspec + `tsc --noEmit`; boot in private mode and confirm business loads
and the generic admin Extensions page works; run the AI smoke harness. Add a grep
gate (CI) failing on new `"business"`/`"trading"` literals in core (excluding the
benign tier/plan names enumerated below).

## Benign (NOT coupling — leave as-is)
Rate-limit/plan **tier** literals named `business` (`rate_limiting/tiered_service.rb`,
`oauth_application.rb`, `webhook_endpoint.rb`, marketplace `tier` unions); skill
type `business_search`; "business value"/"businesses" prose; doc/comment examples;
domain scopes like `for_domain("trading")`. The CI grep gate must allowlist these.

## Notes
- `extensions/private/trading` is referenced only in maintainer-local docs; keep
  its name out of public-facing core per the existing trading code-scrub.
- Phases 3–4 touch the private submodules — follow submodule commit discipline
  (commit inside the submodule first, then bump the pointer).
