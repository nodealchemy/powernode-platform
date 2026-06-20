# Setup Wizard — Design

> Status: **Design / proposed** (not yet implemented). Owner: maintainer. Last updated 2026-06-20.
>
> A first-run, web-based setup experience for new installs **and** an incremental
> per-extension configuration flow, built as a **plugin-based step registry** so core
> and every extension contribute their own steps. Reuse-first: ~80% of the UI already
> exists in `frontend/src/features/onboarding/`.

## 1. Goals

1. Bring a fresh install to a fully-running state from the browser — no manual `rails db:seed`
   / `/etc/powernode/*.conf` editing for the common path.
2. Collect: first admin user + password, domain names / TLS, email (SMTP), general settings,
   and **which extensions to enable** (including private extensions when present on disk).
3. Let **extensions contribute their own wizard steps** (e.g. the system extension contributes
   virtualization-host / cloud-account config; supply-chain contributes scan defaults).
4. Offer to **seed** within the wizard, with the collected domain parameterizing seed data
   (no hardcoded hostnames — see [no-hardcoded-hostnames] thread; seeds default to
   `powernode.internal` only when run headless).
5. **Incremental config**: when a new extension is added later and isn't configured yet,
   surface *only its* steps — the wizard is not a one-time event.

Non-goal (for first-run): *installing* a brand-new extension (submodule add + bundle +
frontend rebuild). The wizard **activates and configures extensions already present in the
build**; physically adding a new extension remains a maintainer/CLI operation that produces a
new build, after which the wizard picks up its steps (§8).

## 2. Reuse-first inventory (what already exists)

| Concern | Existing seam | Use |
|---|---|---|
| Multi-step wizard UI | `frontend/src/features/onboarding/FirstRunWizard.tsx` | Generalize into a registry-driven driver |
| Schema-driven forms | `frontend/.../ProviderCredentialForm.tsx` | Render any step's field schema |
| Onboarding HTTP client | `frontend/.../services/onboardingApi.ts` | Add setup endpoints |
| "Needs onboarding?" gate | `OnboardingGate` in `frontend/src/App.tsx` | Extend to pending-steps gating |
| Backend onboarding | `server/app/controllers/api/v1/onboarding_controller.rb` | Sibling `Setup::` controllers |
| **Extension enablement (runtime)** | `server/app/services/shared/feature_gate_service.rb` (`extension_enabled?`, `set_extension_enabled!`) + `extension_state_store.rb` | Powers the extension-selection step |
| Extension discovery | `server/lib/powernode/extension_registry.rb` + `extensions/*/extension.json` | Step discovery (§4) |
| Settings storage | `SiteSetting` / `AdminSetting` models | Persist email/domain/general settings |
| Completion state | `account.metadata` JSONB (already tracks `onboarding_completed_at`) | Per-step / per-extension stamps |
| Seeding | `server/db/seeds.rb` extension-aware orchestrator | Behind a programmatic "seed if empty" wrapper |
| Frontend build gate | `frontend/vite.config.ts` → `__EXTENSIONS__` (build-time slug list) | Constrains which extension UIs can render (§7) |

## 3. Architecture: a plugin-based step registry

The wizard is **not** a fixed sequence. It is a driver over an ordered list of `SetupStep`s
aggregated from two sources:

- **Core steps** — admin, domain/TLS, email, general settings, extension-selection, seed.
- **Extension steps** — each *enabled* extension contributes zero or more steps.

```
GET /api/v1/setup/status        -> { bootstrap_complete, pending: [{owner, steps[]}] }
GET /api/v1/setup/steps         -> ordered [SetupStep] with schema + completion state
POST /api/v1/setup/steps/:key   -> persist one step's payload, stamp completion
POST /api/v1/setup/admin        -> create the FIRST admin (unauthenticated, §6)
POST /api/v1/setup/seed         -> run the seed wrapper (idempotent, "seed if empty")
```

The frontend `FirstRunWizard` fetches `/setup/steps`, renders each via the schema form (or a
lazy extension component for richer steps), and POSTs each as it completes. This is the same
schema-driven pattern `ProviderCredentialForm` uses today — generalized.

**Two drivers, one registry (decision: include a headless CLI).** The same
`Setup::StepRegistry` and the per-step service objects behind each `:endpoint` back **both**
the web wizard **and** a headless CLI — `rails setup:run --answers setup.yml` — that applies a
YAML answer file for unattended / automated installs. Steps with no answer-file key (or that
can't be answered headlessly) are reported and left pending. One source of truth for what
"configured" means; web and CLI never drift.

## 4. The `SetupStep` contract

Extensions declare steps in their existing `extension.json` manifest (core reads it
generically — it never hard-codes an extension slug):

```jsonc
// extensions/system/extension.json (illustrative)
"setup_steps": [
  {
    "key": "system.virtualization_hosts",
    "title": "Virtualization hosts",
    "order": 50,                       // global ordering; core steps occupy 0–40
    "required": false,                 // required steps block completion; optional can skip
    "depends_on_enabled": "system",    // only surfaces if this extension is enabled
    "schema": [                        // simple steps render from a field schema...
      { "key": "host", "type": "text", "required": true },
      { "key": "token", "type": "password", "required": true }
    ],
    "component": "@ext/system/setup/VirtualizationHostsStep", // ...or a lazy component for rich UI
    "endpoint": "/api/v1/system/setup/virtualization_hosts"   // where POST payload goes
  }
]
```

- `schema` covers the common case (a field list → reuse the existing form renderer).
- `component` is for richer flows (tables, test buttons, multi-add) — lazy-loaded behind the
  build-time `__EXTENSIONS__` gate, so it only loads if the extension is in the build.
- `endpoint` lets the extension own its persistence; core just orchestrates ordering + state.

Backend `Setup::StepRegistry`:
```ruby
Setup::StepRegistry.steps_for(account)
#   core steps (static) +
#   ExtensionRegistry.each { |ext| ext.enabled? ? ext.manifest["setup_steps"] : [] }
#   sorted by :order, annotated with completion state from account.metadata
```

## 5. Requirements → steps

| Requirement | Owner | Notes |
|---|---|---|
| First admin + password | core (order 0, **required**, non-skippable) | unauthenticated endpoint, §6 |
| Domain names / TLS | core (10) | → `Account` + `System::AcmeDnsCredential` |
| Email (SMTP) server | core (20) | → `AdminSetting` (host/port/user/secret-in-Vault/from) |
| General settings | core (30) | → `SiteSetting` (site name, contact, etc.) |
| **Extension selection** | core (40, required) | `FeatureGateService.set_extension_enabled!`; toggling re-computes the step list |
| Git servers | core or git step | reuse existing git-provider onboarding |
| Virtualization hosts / cloud accounts | **system extension** | extension-contributed steps (50+) |
| AI / cloud / git providers | existing onboarding steps | reuse as-is (now part of the registry) |
| Seed offer | core (final) | §9 wrapper |
| Anything else "for a fully running system" | whichever component owns it | new steps slot in by `order` — no core change needed |

## 6. First-run security (the one genuinely new/sensitive piece)

The admin-setup endpoint runs **before any user exists**, so it cannot use JWT. Threat: a
random visitor claims the instance.

- `POST /api/v1/setup/admin` is **unauthenticated** but gated on **two** conditions:
  1. `User.count == 0` for the account (one-shot — once an admin exists, it 409s), and
  2. a one-time **bootstrap token**. On first boot with zero users, the backend generates a
     random token, stores only its **hash** (DB / transient store), and **prints the setup URL
     to the service console** — `https://<host>/setup?token=…` — visible via
     `journalctl -u powernode-backend@default`. **No token file is written to disk** (decision:
     printed URL only).
- The operator copies the printed URL. The endpoint verifies the token against the stored hash
  and invalidates it on first successful admin creation — the token *and* the entire
  unauthenticated path go dead once an admin exists.
- All other setup endpoints are normal authenticated `super_admin` routes (an admin now exists).

This keeps the only unauthenticated surface to a single, self-disabling, token-gated endpoint.

## 7. Extension enablement: build-time vs runtime

Two layers, deliberately:

- **Backend (runtime):** `FeatureGateService.set_extension_enabled!(slug, bool)` →
  `extension_state_store` (a disabled-list file). Effective immediately; gates API + the step
  registry. This is what the **extension-selection step** writes.
- **Frontend (build-time):** `vite.config.ts` bakes `__EXTENSIONS__` = the slugs active *at
  build time*. An extension's UI (incl. its wizard `component`) must be in the build to render.

Reconciliation: the wizard can **activate/deactivate** any extension that is *present in the
build*; its steps then appear/disappear from the registry. An extension that is not in the
build cannot contribute UI until a rebuild — which is the §8 path. The extension-selection
step therefore lists "present in this build" extensions, with their `enabled` toggle.

**Disabling with retention (decision: allowed).** Disabling a built-in extension that already
holds data is permitted, behind a confirm. It is **non-destructive**: `FeatureGateService`
gates the extension's API / UI / wizard steps off, but **all of the extension's data is
retained**. Re-enabling restores access to the existing data, and its `configured_at` stamp
persists so it does not re-prompt for setup. The wizard never deletes extension data; purging
is a separate, explicit maintainer operation outside setup. (The confirm dialog states plainly
that data is kept, not removed.)

## 8. Incremental per-extension configuration (new requirement)

The wizard is not one-shot. Completion is tracked **per step / per extension**:
`account.metadata.setup.extensions.<slug>.configured_at`.

- A newly-added extension (submodule + bundle + **rebuild** done by a maintainer) is, after
  restart, *present in the build* and *enabled by default* but has **no `configured_at`**.
- `GET /api/v1/setup/status` reports it under `pending`. The `OnboardingGate` distinguishes:
  - **bootstrap pending** (admin/domain incomplete) → blocking full wizard;
  - **extension pending only** → a **non-blocking** prompt/banner ("Configure *System*")
    that opens the wizard scoped to just that extension's steps.
- Same driver, same registry — only the pending subset differs. Configuring stamps
  `configured_at`, the prompt clears.

This also handles **enabling** a previously-disabled (but built-in) extension via the
selection step: enabling it makes its steps pending → the same prompt appears.

## 9. Seeding integration

- New `Setup::SeedService.run!(account, only_if_empty: true)` wraps the existing orchestrator
  with a guard (skip files whose target rows already exist) so it is safe from the web.
- The final wizard step offers: "Seed example data?" → calls `POST /api/v1/setup/seed`.
- **Domain parameterization:** seeds read the collected domain (default `powernode.internal`
  when headless) instead of hardcoding hosts — closes the [no-hardcoded-hostnames] thread by
  construction.

## 10. Idempotency & resume

- Every step stamps `account.metadata.setup.steps.<key>.completed_at`.
- The wizard resumes by skipping completed steps (the existing smart-skip logic, generalized).
- Steps are individually re-runnable (each POST upserts).

## 11. Core purity

Core **never names a private extension**. `Setup::StepRegistry` discovers steps from
`extension.json` of whatever extensions are present and enabled. Private extensions' steps
exist only on a checkout that has them; on a public/core-mode install they simply don't appear.
This satisfies the blocking `core-purity-check.sh` (gate #9) the same way the rest of the
extension system does.

## 12. Phased plan

- **Phase 1 — Bootstrap + registry skeleton:** `POST /setup/admin` (token-gated), domain step,
  `Setup::StepRegistry` + `GET /setup/status|steps`, frontend driver reading the registry,
  `OnboardingGate` → pending-steps. *Delivers: browser-based first-login + a working seam.*
- **Phase 2 — Core config steps:** email (SMTP), general settings, extension-selection
  (`FeatureGateService` wiring), seed step (`Setup::SeedService`, domain-parameterized seeds).
- **Phase 3 — Extension-contributed steps:** the `setup_steps` manifest field + lazy
  component loading; first real consumer = the **system** extension's virtualization-host /
  cloud-account steps.
- **Phase 4 — Incremental config:** per-extension `configured_at`, the non-blocking
  "configure newly-added extension" prompt, and the enable→pending flow.

Each phase is independently shippable and testable.

## 13. Decisions (resolved 2026-06-20)

1. **Bootstrap-token delivery** — **printed setup URL** on the service console at first boot;
   token hash stored server-side, single-use, no on-disk token file (§6).
2. **Disabling extensions** — **allowed, non-destructive retention policy**: disabling gates
   access but keeps all data; re-enabling restores it (§7).
3. **Secret storage** — secrets go to **Vault by default**, but Vault is itself globally
   toggleable with a DB-encrypted fallback and bidirectional migration — designed separately in
   [credential-storage-backends-design.md](credential-storage-backends-design.md); the wizard exposes the
   toggle + migration trigger as a settings step.
4. **Headless CLI** — **included**: `rails setup:run` over a YAML answer file, sharing the same
   `Setup::StepRegistry` (§3); Phase 1 ships the seam, coverage grows with each phase.

---

Related: `docs/operations/single-node-bootstrap.md` (current manual path this replaces for the
common case), `docs/contributing/core-extension-decoupling.md` (extension architecture).
