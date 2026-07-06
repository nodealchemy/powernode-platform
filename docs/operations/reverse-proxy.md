# Bundled Reverse Proxy (Traefik) — Architecture, Usage & Improvement Plan

**Status:** Audit + determination (2026-06-15); core/extension ingress seam (§7-8) approved
2026-07-06 and implemented by campaign 019f3458 increment 8. Current-state sections are
authoritative; §7's split is now live (`Core::IngressConfigWriter` + the
`ingress_certs`/`ingress_routers` provider seam) — see the increment-8 note under §4 and §7-8
below.

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

**Per-account routers — 10 per cert** (`ROUTER_SPECS`, `traefik_config_writer.rb:414-425`), all on
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
  hot-reloads — the host gets all 10 routers. The per-cert regen is also exposed as MCP
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
| systemd unit + launcher script | **core** (`scripts/systemd/`) | **Decoupled by increment 8** — the launcher now calls `Core::IngressConfigWriter` (binary resolution checks the extension's vendored path first, then core's own `scripts/systemd/dist/` — `make vendor-traefik` at the repo root); no more hard ref to the extension binary path or `Acme::TraefikConfigWriter`. |
| `Core::IngressConfigWriter` (static config + services + path/host-rule helpers + provider seam + core-mode self-signed baseline) | **core** (`server/app/services/core/`) | **New, increment 8.** `Acme::TraefikConfigWriter` delegates its static-config/services/path-resolution/host-rule methods here instead of duplicating them. |
| `Acme::TraefikConfigWriter`, full `Acme::*` ACME stack | **system ext** | `extensions/system/server/app/services/acme/` — registered as BOTH the `ingress_certs` and `ingress_routers` providers (`lib/powernode_system/engine.rb`); `Core::IngressConfigWriter.write!` delegates the entire per-account write to it when present (byte-identical to pre-seam output), nil ⇒ core baseline. |
| `System::AcmeCertificate` model + migration | **system ext** | cert source for routers |
| `Api::V1::System::IngressRoutesController` (read-only) | **system ext** | derived projection of routers |
| `reverse_proxy_compose_executor` (MCP skill) | **system ext** | thin per-account regen |
| `internal/reverse_proxy_controller` | **core** | LEGACY config-text generator; worker-only; not the running proxy |
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

## Ratified decisions — campaign 019f3458 (2026-07-05)

Campaign `019f3458-e607-7528-937d-3c159f097901` (Reverse-Proxy/SDWAN Export Hardening +
Ops-Tier Rebuild on Proxmox) settled how public/federated TCP, TLS, and UDP traffic is routed,
and scoped the §7-8 core/extension split below. Nothing in this section is implemented yet —
each bullet lands as its own individually-approved campaign increment (numbers below refer to
that campaign's increment table).

- **Capability-tiered hybrid, not a single mechanism.** Public **TLS-carrying TCP** (traffic
  that presents a TLS ClientHello with SNI) rides **Traefik `tcp.routers`** — on the **existing**
  `websecure` entrypoint only. **All UDP, non-SNI plaintext TCP, and source-IP-sensitive
  services stay on nftables DNAT** (`Sdwan::PortMapping` → `Sdwan::NatCompiler`) **permanently —
  no new Traefik entrypoints, ever.** (Increments 5, 6.)
- **`edge_mode` on `Sdwan::Service`** (landed with increment 5; `public_enabled` is settable, in
  either direction, only via `System::Ai::Skills::ExposeServicePublicTcpExecutor` — MCP actions
  `system_expose_service_public_tcp` / `system_unexpose_service_public_tcp`, the increment 10
  prerequisite for improvement `019f34f9`): defaults to
  **`passthrough`** (Traefik forwards the encrypted stream untouched; the backend terminates
  TLS); **`terminate`** is opt-in (Traefik terminates via its own ACME cert); **proxy-terminated
  mTLS ships in v1** (client-cert enforcement at the Traefik edge, not deferred to a later
  version).
- **Federated `tcp`-protocol subscriptions move off Traefik entirely**, onto the site-local
  `tcpfwd` daemon (the Go agent's `internal/tcpfwd` package, already implemented and tested on
  the agent side — `extensions/system/agent/internal/tcpfwd/`). Federated `tls`-protocol
  subscriptions (which do carry SNI) stay on Traefik, once increment 4 fixes the bugs below.
- **The §7-8 core/extension provider seam is scoped to `:80`/`:443` only** — it carries the
  existing HTTP(S) router baseline (`Core::IngressConfigWriter` + provider injection), not the
  TCP/TLS/UDP paths above. It lands as campaign increment **8**, gated on increments 4, 5, and 7
  landing first and on a separate operator go/no-go for the seam shape.

### `ServiceRouteWriter` bugs — FIXED by increment 4 (historical)

`Federation::ServiceRouteWriter`
(`extensions/system/server/app/services/federation/service_route_writer.rb`) used to emit live
Traefik `tcp.routers` for federated `tcp`/`tls` subscriptions with three confirmed bugs
(re-verified directly against the file on 2026-07-05). All three are **FIXED as of increment 4**:

- **`tcp`-protocol subscriptions could never match. FIXED.** `add_tcp_route!` was invoked for
  both `"tcp"` and `"tls"` protocols and unconditionally emitted a `HostSNI` rule — but plaintext
  TCP carries no TLS ClientHello for Traefik to read an SNI value from, so a `tcp`-protocol router
  could never route real traffic. **Now:** `ServiceRouteWriter` no longer emits a Traefik router
  for `tcp`-protocol subscriptions at all; they route via the `tcpfwd` daemon instead
  (`Federation::TcpForwarderConfigWriter`, increment 3's writer, whose selection increment 4
  broadened from site-local-only to site-local-or-`tcp`-protocol).
- **The `tls` branch never set `passthrough: true`. FIXED.** It set `router["tls"] = {}` for
  `protocol == "tls"` but never added a `passthrough` key — so Traefik attempted to terminate TLS
  itself (passthrough defaults to `false`) instead of forwarding the encrypted stream to the
  backend, a silent mis-termination. **Now:** the `tls` branch sets
  `"tls" => { "passthrough" => true }`.
- **The `tls` branch never set `entryPoints`. FIXED.** No entry in the router hash built by
  `add_tcp_route!` set `entryPoints` — Traefik routers with no `entryPoints` key bind **every**
  entrypoint matching the protocol, including the plaintext `web` (`:80`) entrypoint alongside
  `websecure` (`:443`). **Now:** the router explicitly sets `entryPoints: ["websecure"]`.

`Federation::TcpForwarderConfigWriter`
(`extensions/system/server/app/services/federation/tcp_forwarder_config_writer.rb`, built in
increment 3) now exists and, as of increment 4, selects both site-local subscriptions and any
`tcp`-protocol subscription (site-local or not) — matching `ServiceRouteWriter`'s narrowed
selection so exactly one writer runs per subscription. The Go agent's `powernode-agent service`
loop (`extensions/system/agent/internal/runtime/service.go`) now loads and runs the `tcpfwd`
daemon at startup from `tcpfwd.DefaultConfigPath` (load-at-start only; reload-on-change is not yet
supported — an agent restart is required to pick up new/changed forwards).

---

## 7. Determination — core vs `system` extension (Approved 2026-07-06, implemented by increment 8)

**A tiered split via the existing `ExtensionRegistry` provider seam — not a wholesale move.**

- **A minimal "core ingress baseline" now lives in core** (`Core::IngressConfigWriter`,
  `server/app/services/core/`): the static config + the `api`/`agent`/`cable`/`frontend` routers + a
  self-signed cert for the host, plus core acquisition of the vendored Traefik binary (`make
  vendor-traefik` at the repo root, mirroring the extension's target into
  `scripts/systemd/dist/`). This gives **core mode** a working HTTPS ingress with zero extension —
  directly enabling external-proxy retirement on self-hosted single-node installs. The static
  config + services + path-resolution + host-rule helpers (zero `System::` dependency to begin
  with) were LIFTED out of `Acme::TraefikConfigWriter` into `Core::IngressConfigWriter`; the
  extension's methods of the same name now delegate to core (one-liners) instead of duplicating
  the logic, so the two writers can't drift apart.
- **Advanced ingress stays in the `system` extension**: per-account ACME (DNS-01 + providers), the
  mTLS CA bundle + `_mtls.yaml`, and the federation/worker/`node_api`/Sidekiq routers.
  `Acme::TraefikConfigWriter` is registered as BOTH the `:ingress_certs` and `:ingress_routers`
  providers (`lib/powernode_system/engine.rb`) — it already owns cert selection and router
  rendering together as one cohesive per-account write, so `Core::IngressConfigWriter.write!` asks
  `ExtensionRegistry.provider(:ingress_certs)` / `provider(:ingress_routers)` and, when BOTH resolve
  to the SAME registered object, delegates the ENTIRE per-account write to it, unchanged — this is
  what guarantees byte-identical output vs. the pre-seam code path (verified: `diff -r` across a
  full pre/post config generation, plus an automated spec,
  `extensions/system/server/spec/integration/core_ingress_seam_spec.rb`). Nil (or a provider
  registering only one facet) ⇒ core baseline. **Zero core→extension coupling**; a future extension
  can inject ingress behavior with no core edit.
- **The launcher's latent coupling is fixed**: `scripts/systemd/powernode-reverse-proxy.sh` no
  longer hard-codes the extension binary path or `Acme::TraefikConfigWriter` — it calls
  `Core::IngressConfigWriter`, which delegates to the provider if present, else the baseline. Binary
  resolution checks the extension's vendored path first (existing installs unaffected), then core's
  own vendored copy.

Why not the alternatives:
- *Leave entirely in system ext* — simplest, but core mode still can't drop an external proxy, and the
  launcher's core→extension coupling (an Extension-Isolation violation) remains.
- *Full move to core* — drags `FederationPeer`, `InternalCaService`, DNS-01 issuance, and per-account
  multi-tenancy into core; contradicts Extension Isolation and the decoupling effort.

## 8. Phased plan

1. **Quick fixes — DONE.** G3 empty-cert guard; G4 doc corrections. (The dead
   `admin/reverse_proxy_controller.rb` was already removed in the same commit that introduced this
   doc — `643619f3`, 2026-06-15.)
2. **Core ingress baseline (Phase A) — DONE (increment 8).** `Core::IngressConfigWriter` (static +
   4 generic routers + self-signed cert); core binary acquisition (`make vendor-traefik` at the
   repo root); launcher delegates via the provider seam; both-mode output verified (core mode:
   static + 4 generic routers + self-signed cert stanza, sanity-checked via a simulated
   extension-absent generation; extension mode: `diff -r` byte-identical against the pre-seam
   output, plus the automated `core_ingress_seam_spec.rb` regression pin).
3. **System ext as ingress provider (Phase B) — DONE (increment 8).** `Acme::TraefikConfigWriter`
   registered under both `:ingress_certs` and `:ingress_routers`; the ACME/mTLS/federation/worker
   router emission stays behind it, invoked via full delegation when both keys resolve to the same
   object; `Sdwan::ServiceExposureWriter` (local-services plane) and `Federation::ServiceRouteWriter`
   / `Federation::TcpForwarderConfigWriter` (TCP/TLS tiers) are untouched — verified via their
   existing spec suites, unmodified.
4. **Custom routes (G1) — already delivered pre-increment-8** via the Service Exposure Subsystem
   (`Sdwan::Service`, §6) — not part of this seam.
5. **Verify & document — DONE for increment 8's scope.** Core writer specs + extension
   provider-registration spec + the automated byte-identical seam spec, all green; full
   `spec/services/acme/`, `sdwan/service_exposure_writer_spec.rb`,
   `federation/service_route_writer_spec.rb`, and the MCP ingress request specs re-run green;
   pattern-validation 43/43; this doc updated. Broader both-mode AI/UI smoke coverage remains a
   follow-up, not blocking this increment.

Cross-repo commit discipline: control-plane changes land **inside `extensions/system`** first
(push both `origin` (Gitea) + `github` (public mirror)), then core/parent pointer + core baseline.
