# Extensions and Core Mode

> How Powernode's extension model works, what is public, what is private, and what changes when an extension is absent.

> Status: active

Powernode separates the open-source core from optional capability bundles called **extensions**. Each extension is a git submodule under `extensions/`. Extensions depend on the core; the core never depends on an extension. When an extension is absent the platform falls back to **core mode** automatically — no manual configuration required.

## Table of Contents

- [The extension model](#the-extension-model)
- [The four extensions](#the-four-extensions)
- [Core mode vs extension mode](#core-mode-vs-extension-mode)
- [Working with submodules](#working-with-submodules)
- [Feature gating](#feature-gating)
- [Why this split exists](#why-this-split-exists)
- [Adding or developing an extension](#adding-or-developing-an-extension)

## The extension model

The core platform is everything outside `extensions/`. It ships:

- The Rails 8 API server (`server/`)
- The React frontend (`frontend/`)
- The standalone Sidekiq worker (`worker/`)
- The shared docs, scripts, and CI under the repo root

Each extension under `extensions/<name>/` is a self-contained git submodule with its own backend code, frontend code, seeds, and docs. Extensions are loaded by the platform's autoloader when they are present. When an extension's directory is missing or empty, the platform skips it. `config/extensions_state.json` records the on-disk state per extension (`enabled` vs `disabled`).

## The four extensions

| Extension | Submodule path | Visibility | Purpose |
|-----------|----------------|------------|---------|
| `system` | `extensions/system` | **Public** (GitHub mirror, MIT) | Node lifecycle, modules, SDWAN, fleet autonomy, container runtimes, on-node Go agent |
| `marketing` | `extensions/marketing` | **Public** (GitHub mirror, MIT) | Marketing site assets |
| `supply-chain` | `extensions/supply-chain` | **Public** (GitHub mirror, MIT) | Supply-chain extension scaffolding |
| `business` | `extensions/private/business` | **Private** (Gitea only) | Billing, BaaS, reseller, AI publisher — the commercial features |

External clones from the public GitHub mirror will receive the three public extensions plus an empty parent pointer for the private `business` extension; the platform will boot in "core mode minus business" by default.

The public submodules are dual-remoted: `origin` points at the public GitHub mirror, and `ipnode` points at the private Gitea upstream (used for releases). Maintainers push to both; external contributors only ever see the GitHub side.

**Private and custom extensions** live under `extensions/private/<slug>/`. The entire `extensions/private/` directory is gitignored (it also matches the `*private*` rule in `.gitignore`), so anything placed there is never committed to the parent repo and never appears in public clones — no per-extension `.gitignore` entry, and no private name advertised in tracked files. The commercial `business` extension lives at `extensions/private/business`; maintainers drop additional private or local extensions alongside it. Discovery (Vite, the worker boot scanners, and the Rails feature gate) scans **both** `extensions/<slug>/` and `extensions/private/<slug>/`, so a private extension loads identically to a public one — the only difference is that its files stay out of git. The slug is always the leaf directory name (`business`), never `private`.

## Core mode vs extension mode

| Mode | What's available | Who runs in this mode |
|------|------------------|----------------------|
| **Core mode** | Single-user, self-hosted, all features unlocked, no billing/SaaS workflows | External contributors who clone from GitHub; anyone running Powernode privately |
| **Business mode** | Multi-tenant, billing, plans, subscriptions, BaaS, reseller — gated behind the `business` extension | Powernode-hosted SaaS deployments |

Core mode is the default. When the platform boots with no `extensions/private/business/` directory:

- The `Shared::FeatureGateService.business_loaded?` check returns `false`.
- All paywalls and plan-limits short-circuit (everything is "allowed").
- The frontend's `__EXTENSIONS__` build constant omits `'business'`, so `__EXTENSIONS__.includes('business')` is `false` and the business UI surfaces are hidden.

There is nothing to configure — you get this automatically.

## Working with submodules

Each extension is a separate git repository. The parent repo only tracks the SHA pointer. Common operations:

```bash
# Initialize all submodules after cloning
git submodule update --init --recursive

# Pull the latest of every submodule
git submodule update --remote --recursive

# Check submodule state from the parent
git submodule status

# Inside a submodule: same git commands as any repo
cd extensions/system
git status
git log --oneline -10
```

Three rules matter when committing:

1. **CWD verification.** Before EVERY `git add` or `git commit`, run `git rev-parse --show-toplevel` and confirm you are in the intended repo. Files under `extensions/<name>/` MUST be committed from inside the submodule.
2. **Commit order.** Commit inside the submodule first, then update the pointer in the parent.
3. **Do not `git submodule sync` on dual-remoted public extensions.** It overwrites local config and drops the private upstream remote.

## Feature gating

Three mechanisms gate features:

- **Backend:** `Shared::FeatureGateService.business_loaded?` (or the equivalent for another private extension) controls model instantiation, controller availability, and skill registration.
- **Frontend:** Vite injects the `__EXTENSIONS__` constant (an array of enabled extension slugs) at build time; UI surfaces gate on `__EXTENSIONS__.includes('business')` and hide when the extension is absent.
- **Navigation:** the nav config checks extension-slug presence via `__EXTENSIONS__.includes(slug)` so disabled extensions disappear cleanly from the sidebar.

A feature that crosses the boundary should pick one mechanism and stick with it. Never use two — the result is invariably a half-hidden surface that confuses users.

## Why this split exists

The split serves three goals:

1. **OSS-first license posture.** The core and the system extension ship under MIT so anyone can self-host the fleet-management proposition.
2. **Commercial sustainability.** Billing, BaaS, reseller, and AI-publisher features are non-trivial to build and maintain. Keeping them in a private extension lets us fund development without compromising the open core.
3. **Independent release cadence.** Each extension can ship at its own pace. The system extension has been the most active recently; the marketing site can iterate without forcing a parent release.

## Adding or developing an extension

Plans, executor patterns, and the FeatureGateService contract are documented in [guides/extensions.md](../guides/extensions.md). The system extension is the canonical exemplar — its layout (`server/`, `agent/`, `extensions/system/initramfs/`, `cli/`, `docs/`, `db/seeds/`) covers every pattern a new extension is likely to need.

---

## Materials previously at

- The "Business Submodule" section of the root CLAUDE.md
- The "Submodule Safety" section of the root CLAUDE.md

_Last verified: 2026-06-04_
