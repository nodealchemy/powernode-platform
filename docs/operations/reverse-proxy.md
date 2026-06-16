# Bundled Reverse Proxy (Traefik) — Architecture, Usage & Improvement Plan

**Status:** Audit + determination (2026-06-15). Current-state sections are authoritative;
the "Proposed" section is a plan pending maintainer decision (not yet implemented).

Powernode ships a **bundled reverse proxy** so an install can terminate TLS and serve its
own API + frontend on :80/:443 without a separate, hand-configured external proxy. This doc
describes what it is, how it actually works, how to use it, its current health, and a plan
to (a) let it fully replace an external proxy and (b) resolve where it should live
(core vs the `system` extension).

> **Terminology trap.** "Reverse proxy" means **two unrelated things** in this codebase:
> 1. **The bundled Traefik** (this doc) — the live process that serves traffic. Config is
>    generated from Rails by `Acme::TraefikConfigWriter` (in the `system` extension).
> 2. **A legacy "Services Configuration" feature** in core (`ServicesController` +
>    `url_mappings` + the `ServiceConfiguration` concern, plus the older
>    `internal/` and `admin/` `reverse_proxy_controller`s) that only **generates
>    nginx/apache/traefik config *text* for an EXTERNAL proxy** and writes nothing to the
>    running Traefik. Do not confuse the two.

---

## 1. Current state — it is functional

- Unit: `powernode-reverse-proxy@default.service` — **active (running)**, `PartOf=powernode.target`,
  runs as user `rett` on **:80 and :443** via the `CAP_NET_BIND_SERVICE` ambient capability
  (not root). Unit: `scripts/systemd/units/powernode-reverse-proxy@.service`.
- Binary: **vendored upstream Traefik v3.3.2**, `extensions/system/agent/dist/powernode-reverse-proxy-linux-amd64`
  (an asset — gitignored, fetched + renamed by `make vendor-traefik`; **not** custom Go).
- Live behavior (probed): `:80/ → 301 https`, `:443 /api/v1/health → 200`, `:443 / → 200`.
- Known issues:
  - One per-account ACME cert file is empty → Traefik logs
    `failed to find any PEM data in certificate input` and skips it (non-fatal). See §5.
  - Cosmetic: upstream Traefik 3.7.5 available (vendored is 3.3.2).

## 2. How it works (the real bundled proxy)

**Single source of truth = Rails.** Traefik holds no hand-written config. At each start the
launcher `scripts/systemd/powernode-reverse-proxy.sh` runs a `rails runner` that calls
`Acme::TraefikConfigWriter` (`extensions/system/server/app/services/acme/traefik_config_writer.rb`)
to regenerate config, then execs Traefik with the generated static file.

Generation order (matters — mTLS shared config + CA must exist before per-account routers ref them):

1. `write_internal_ca!` → `<ca_dir>/internal-ca.pem` (our CA; node/worker identity anchor).
2. `write_mtls_shared_dynamic!` → `<ca_dir>/client-auth-bundle.pem` (our CA **+** `System::FederationPeer.trusted_ca_pems`)
   and `<dynamic_dir>/_mtls.yaml` (`mtls-optional` TLS option = `VerifyClientCertIfGiven`,
   `pass-tls-client-cert` middleware forwarding `X-Forwarded-Tls-Client-Cert[-Info]`).
3. `Account.find_each → write!(account:)` → `<dynamic_dir>/acme-<account_id>.yaml` (per-account routers,
   one file per account, built from that account's `valid` `System::AcmeCertificate` rows).
4. `write_static_config!` → `traefik.yaml` (path printed to stdout, passed to `--configFile`).

**Static config** (`traefik.yaml`): `web` entrypoint (:80) with a blanket permanent redirect to
`websecure` (:443); `websecure` carries the `pass-tls-client-cert@file` middleware; `file` provider
on `<dynamic_dir>` with **`watch: true`** (dynamic routers/certs **hot-reload without a restart**;
only static-config changes need a service restart); dashboard off.

**Per-account routers — 9 per cert** (`ROUTER_SPECS`, `traefik_config_writer.rb:376-386`), all on
`websecure`, each `tls.options: mtls-optional@file`, ordered by path specificity:

| Router | Rule | Upstream |
|---|---|---|
| `node-api` | Host + `PathPrefix(/api/v1/system/node_api)` | `powernode-backend` (:3000) — mTLS |
| `federation-api` | Host + `/api/v1/system/federation_api` | backend — mTLS |
| `internal-api` | Host + `/api/v1/internal` | backend — mTLS |
| `worker-api` | Host + `/api/v1/system/worker_api` | backend — mTLS |
| `worker-auth` | Host + `/api/v1/worker_auth` | backend — mTLS |
| `api` | Host + `/api` | backend |
| `agent` | Host + `/agent` | backend |
| `cable` | Host + `/cable` | backend (ActionCable WebSocket) |
| `sidekiq` | Host + `/sidekiq` | `powernode-worker-web` (:4567) — Sidekiq dashboard, `SidekiqWebAuth`-gated |
| `frontend` | Host only (catch-all) | `powernode-frontend` (:3001) |

Host matcher = the cert's CN, OR-expanded with `POWERNODE_PROXY_EXTRA_HOSTS`. Upstreams come from
env (`POWERNODE_PROXY_BACKEND_URL` default `http://127.0.0.1:3000`, `POWERNODE_PROXY_FRONTEND_URL`
default `:3001`, `POWERNODE_PROXY_WORKER_WEB_URL` default `:4567`), all `passHostHeader: true`.
**There are three fixed upstreams (backend, frontend, worker-web) and the router set is a frozen
constant** — see §6.

> Traefik forwards WebSocket upgrades transparently, so `/cable` (ActionCable) and Vite HMR work with
> no nginx-style `Upgrade`/`Connection` header plumbing. (The docs that imply `/cable` and the
> frontend are unsupported are **wrong** — corrected here from code + live probe.)

**TLS / ACME** (`certificate_manager.rb`, `lego_client.rb`, `dns_provider_registry.rb`): issuance is
**DNS-01 only** (TLS-ALPN/HTTP-01 are schema-reserved but not wired). Providers: cloudflare, route53,
gcloud, digitalocean, hetzner, porkbun, ovh. PEM material lives in **Vault**; Traefik reads on-disk
copies under `<cert_dir>/<account_id>/<cert_id>.{crt,key}`. Renewal: worker cron → `/api/v1/system/worker_api/acme/renewal_sweep`
→ `RenewalSweepService` (30-day window). Path resolution for all dirs: `POWERNODE_TRAEFIK_*` env →
`/etc/traefik/*` (if writable) → `<Rails.root>/tmp/traefik/<env>/*`.

**mTLS / federation**: `_mtls.yaml` + the two CA files let agents/workers/peers present client certs on
the same :443; `pass-tls-client-cert` forwards them; the `node_api`/`federation_api`/`worker_api`
controllers re-verify via core `Security::MtlsTrust`. This is fleet/federation machinery.

## 3. How to use it

- **Serve a public hostname (platform's own API+frontend):** issue an `AcmeCertificate` whose CN is the
  hostname (UI `/app/system/ingress` → Expose Service, or MCP `system_expose_service_publicly`,
  approval-gated). Once a `valid` cert exists, the account's `acme-<id>.yaml` is (re)written and Traefik
  hot-reloads — the host gets all 9 routers. The per-cert regen is also exposed as MCP
  `system_reverse_proxy_compose` (input: `certificate_id`).
- **Front an externally-terminated hostname onto the same backend:** set `POWERNODE_PROXY_EXTRA_HOSTS`
  (adds OR'd `Host()` matchers; no cert claimed).
- **Point upstreams elsewhere:** `POWERNODE_PROXY_BACKEND_URL` / `POWERNODE_PROXY_FRONTEND_URL`.
- **`scripts/manage-proxy-hosts.sh`** manages the app-level **trusted-host allowlist** in
  `AdminSetting.reverse_proxy_url_config` (CORS / Vite `allowedHosts`) — it does **not** configure
  Traefik routers. Don't reach for it expecting to add proxy routes.

## 4. Component ownership (core vs `system` extension)

| Component | Location | Notes |
|---|---|---|
| systemd unit + launcher script | **core** (`scripts/systemd/`) | But launcher hard-refs the extension binary + `Acme::TraefikConfigWriter` (latent coupling). |
| `Acme::TraefikConfigWriter`, full `Acme::*` ACME stack | **system ext** | `extensions/system/server/app/services/acme/` |
| `System::AcmeCertificate` model + migration | **system ext** | cert source for routers |
| `Api::V1::System::IngressRoutesController` (read-only) | **system ext** | derived projection of routers |
| `reverse_proxy_compose_executor` (MCP skill) | **system ext** | thin per-account regen |
| `internal/reverse_proxy_controller` | **core** | LEGACY config-text generator; worker-only; not the running proxy |
| `admin/reverse_proxy_controller` | **core** | **DEAD** — unrouted, missing worker jobs, stubbed methods |
| `ServicesController` + `url_mappings` + `ServiceConfiguration` concern | **core** | LIVE legacy: generates external-proxy config text; `AdminSetting`-backed, single-tenant |
| `manage-proxy-hosts.sh` (+ its `AdminSetting` methods) | **core** | trusted-host allowlist only |

**Dependency direction:** core application code never references the `Acme::`/`System::` proxy stack
(clean). The *only* core→extension coupling is in the launcher **script** (binary path + the
`TraefikConfigWriter` constant). So in **pure core mode (no `system` extension) the bundled proxy cannot
start** (binary absent + uninitialized constant → `exit 1`).

## 5. The empty-cert error

A `valid` `System::AcmeCertificate` row whose on-disk `.crt` is blank/stale: `materialize_to_disk!`'s
`atomic_write` **skips blank content** (writes nothing), so if a `valid` row's `cert_pem` was ever
blank (lego returned empty / partial materialize), the referenced `certFile` is missing or holds an
earlier stub, and Traefik logs `failed to find any PEM data`. Fix options: re-issue the cert, or add a
guard that won't emit a `tls.certificates` entry for a cert whose on-disk PEM is absent/invalid.

---

## 6. Eliminating the external proxy — corrected gap analysis

The bundled proxy **already** terminates TLS and does the `/api` + `/cable` + frontend split with
transparent WebSocket support. So for the platform's **own** traffic, retiring the external proxy is
mostly a matter of:

1. Point the public hostname's DNS at this host and **issue an ACME cert for it** (or set
   `POWERNODE_PROXY_EXTRA_HOSTS` if TLS stays external during cutover). Then all 9 routers serve it.

The genuine gaps:

- **G1 — Arbitrary custom routes — DELIVERED (2026-06-15) via the Service Exposure Subsystem.**
  `ROUTER_SPECS` stays frozen with its fixed platform upstreams (backend/frontend/worker-web/`/sidekiq`),
  but arbitrary custom routes to **other** services (e.g. `/grafana` → some overlay host) are now a
  first-class model: **`Sdwan::Service`** (system ext). Each service can be exposed **locally** at
  `/svc/<slug>` on the platform's own host(s), authenticated by a Traefik **ForwardAuth** middleware
  (`public | authenticated | scoped`), and/or **federated** to other sites via the existing
  `Federation::ServiceOffering` machinery. Local routes are emitted by a **dedicated**
  `Sdwan::ServiceExposureWriter` into `local-services-<account>.yaml` — `Acme::TraefikConfigWriter`
  is untouched (distinct key namespaces: `<slug>-*` platform, `localsvc-*` local, `sub-*` federation).
  Operate it via the `SystemIngressTool` MCP actions (`system_create_service`, `system_expose_service_local`
  [approval-gated], `system_list_services`, `system_unexpose_service_local`, …) or the Concierge
  skill **Expose Service Locally**. Runbook: [`extensions/system/docs/runbooks/publish-service.md`](../../extensions/system/docs/runbooks/publish-service.md).
  *Note:* the legacy core `url_mappings` (`ServiceConfiguration` concern) still only emits external-proxy
  config text and is NOT wired into the bundled proxy — `Sdwan::Service` is the bundled-proxy path.
- **G2 — Core-mode ingress.** A pure-core single-node install has no working bundled proxy (§4),
  yet that's exactly the user who most wants to drop an external proxy.
- **G3 — Empty-cert robustness** (§5).
- **G4 — Docs drift.** Docs imply the bundled proxy can't serve the frontend/`/api`/`/cable`; it can.

---

## 7. Determination — core vs `system` extension (Proposed, pending decision)

**Recommendation: a tiered split via the existing `ExtensionRegistry` provider seam — not a wholesale
move.**

- **Move a minimal "core ingress baseline" into core**: the static config + the
  `api`/`agent`/`cable`/frontend routers + a self-signed (or single-domain HTTP-01/TLS-ALPN) cert for the
  host, plus core acquisition of the vendored Traefik binary. This gives **core mode** a working HTTPS
  ingress with zero extension — directly enabling external-proxy retirement on self-hosted single-node
  installs. (~40% of `TraefikConfigWriter` — the static config + services + generic routers — has zero
  system dependency and lifts almost verbatim.)
- **Keep advanced ingress in the `system` extension**, injected through the provider seam this session's
  decoupling work already established: per-account ACME (DNS-01 + providers), the mTLS CA bundle +
  `_mtls.yaml`, and the federation/worker/`node_api` routers. Core's writer calls
  `ExtensionRegistry.provider(:ingress_certs)` / `provider(:ingress_routers)` and falls back to the
  baseline when nil (nil ⇒ core mode). **Zero core→extension coupling**; a future extension can inject
  ingress behavior with no core edit.
- **Fix the launcher's latent coupling**: stop hard-coding the extension binary path + `Acme::TraefikConfigWriter`;
  call a core entrypoint that delegates to the provider if present, else the baseline.

Why not the alternatives:
- *Leave entirely in system ext* — simplest, but core mode still can't drop an external proxy, and the
  launcher's core→extension coupling (an Extension-Isolation violation) remains.
- *Full move to core* — drags `FederationPeer`, `InternalCaService`, DNS-01 issuance, and per-account
  multi-tenancy into core; contradicts Extension Isolation and the decoupling effort.

## 8. Proposed phased plan (pending decision)

1. **Quick fixes (low risk, independent of the strategic choice):** G3 empty-cert guard; G4 doc
   corrections; remove the dead `admin/reverse_proxy_controller.rb` (+ confirm no routes/specs).
2. **Core ingress baseline (Phase A of the tiered split):** `Core::IngressConfigWriter` (static + generic
   routers + self-signed/single-domain cert); core binary acquisition; launcher delegates via provider
   seam; both-mode boot smoke (core mode: serves :443 self-signed; private mode: unchanged).
3. **System ext as ingress provider (Phase B):** register `:ingress_certs` / `:ingress_routers`
   providers; move the ACME/mTLS/federation router emission behind them; verify hot-reload + federation
   unaffected.
4. **Custom routes (G1):** add an account-scoped (system) / global (core) custom-route model — or wire
   the existing `url_mappings` — into the writer so operators define `Host + PathPrefix → upstream`
   routes; UI + MCP surface; this is what lets custom external-proxy paths move in.
5. **Verify & document:** both-mode tests, `tsc`/specs, update this doc + the system ingress docs, AI smoke.

Cross-repo commit discipline: control-plane changes land **inside `extensions/system`** first
(public mirror — push both `origin` + `ipnode`), then core/parent pointer + core baseline.
