# System Extension — Threat Model

**Status:** Living document. Last revised 2026-05-03.
**Scope:** Powernode `system` extension and its on-node Go agent. Adjacent
threat surfaces (parent platform JWT auth, Stripe billing in business
extension, AI agent autonomy) cross-reference but are out of scope here.

This document uses **STRIDE** (Spoofing / Tampering / Repudiation /
Information disclosure / Denial of service / Elevation of privilege) to
enumerate threats per attack surface, with mitigations and residual risk.

---

## 1. Attack surfaces

The system extension exposes six logical attack surfaces. Each has a
distinct trust boundary and authentication model.

| # | Surface | Trust boundary | Authentication |
|---|---|---|---|
| S1 | Operator API (`/api/v1/system/*`) | Authenticated operators in a Powernode account | JWT (user) + per-action permission |
| S2 | Worker API (`/api/v1/system/worker_api/*`) | Sidekiq workers acting on behalf of the platform | X-Worker-Token + per-action permission on `Worker` capability |
| S3 | Node API (`/api/v1/system/node_api/*`) | Running NodeInstances reporting their state and fetching config | mTLS (NodeCertificate) OR Instance JWT (X-Instance-Token) |
| S4 | MCP tools (`platform.system_*`) | Claude Code sessions + AI agents | OAuth-bound MCP session + per-action permission |
| S5 | Internal CA / Vault | Production Vault PKI mount + transit | AppRole (server) + Shamir / auto-unseal |
| S6 | Public mirror (GitHub `rett/powernode-system`) | World-readable; MIT-licensed | None (read-only by design) |

A 7th de facto surface: the on-node Go agent's local IPC and the dracut
initramfs identity claim. Those are covered in §3.

---

## 2. Per-surface STRIDE table

### S1 — Operator API

| Threat | Vector | Mitigation | Residual |
|---|---|---|---|
| **S**poofing | Stolen JWT | Per-account isolation enforced via `current_account.system_*` scopes; JWTs short-lived (1h); refresh rotation | LOW — depends on operator credential hygiene |
| **T**ampering | Direct DB write to bypass AASM | All controllers route through services that fire AASM events; AASM `whiny_transitions: true` blocks invalid moves | LOW |
| **R**epudiation | Operator denies an action | Every mutation logs to `System::FleetEvent` with operator identity + correlation_id; events retained 90d (routine) / 365d (high+critical) | LOW |
| **I**nfo disclosure | Cross-tenant leak via missing `current_account` filter | Account decorator at `account.rb` exposes 17+ `has_many` helpers; cross-tenant denial specs cover top controllers | MEDIUM — every new controller is a fresh opportunity |
| **D**oS | Malicious large query | Rate limiting at reverse proxy; per-account quotas planned but NOT yet enforced (see system_review_and_plan.md §5 P3 #18) | MEDIUM — quotas are deferred |
| **E**op | Permission escalation via mass-assignment | Strong Parameters in every controller; `permit(...)` allowlists | LOW |

### S2 — Worker API

| Threat | Vector | Mitigation | Residual |
|---|---|---|---|
| **S**poofing | Stolen worker token | Tokens rotated via `WorkerService.rotate_token`; X-Worker-Token over TLS only | LOW |
| **T**ampering | Worker fakes task completion | Server validates `claimed_by_worker_id` matches the calling token; AASM `whiny_transitions` blocks invalid completes | LOW |
| **R**epudiation | Worker denies an event | `claimed_by_worker_id` column populated on every claim/run; `task.events` JSON column logs handoffs | MEDIUM — per system_review_and_plan §3.1, `task.events` JSON is hard to query at scale |
| **I**nfo disclosure | Worker pulls another account's task | `worker_api/tasks_controller#pending` filters by worker's account; cross-account denial spec | LOW |
| **D**oS | Worker spam-creates events | `FleetEvent` retention sweep auto-deletes routine events ≥90d old; per-worker rate limiting NOT enforced | MEDIUM — relies on retention rather than admission control |
| **E**op | Worker compromises a node it shouldn't have access to | Per-account scoping; worker can only execute tasks for nodes in its account | LOW |

### S3 — Node API (the highest-impact surface)

| Threat | Vector | Mitigation | Residual |
|---|---|---|---|
| **S**poofing | Replay another node's certificate | mTLS terminates at reverse proxy + cert pinning; `NodeCertificate` rows tracked with active/revoked status; cert rotation at 75% of 90-day TTL | LOW once Vault PKI mount lands; **MEDIUM today** (Vault PKI not mounted in production — see §5 below) |
| **T**ampering | Node submits forged metrics or events | Server records source identity on every event; suspicious patterns (impossible heartbeat cadence, mismatched correlation_id) flagged via `HoneypotAccessSensor` + `AttributeFailureExecutor` | LOW |
| **R**epudiation | Node denies running a task | Task lifecycle events tracked server-side; agent heartbeat carries last completed task ID | LOW |
| **I**nfo disclosure | Node reads another node's config | `node_api/config_controller` filters by certificate's bound `node_instance_id`; cross-instance denial spec | LOW |
| **D**oS | Compromised node floods the platform with events | Per-instance rate limit + retention sweep; emergency_halt MCP tool can disable the entire node API surface | MEDIUM — admission control is best-effort |
| **E**op | Node escapes to operator capabilities | Cert is bound to `node_instance_id`; node API controllers reject any operator-level path attempts | LOW |

### S4 — MCP tools

| Threat | Vector | Mitigation | Residual |
|---|---|---|---|
| **S**poofing | Compromised Claude session | OAuth tokens via SSE daemon; sessions tied to specific OAuth app + user identity | LOW |
| **T**ampering | Tool dispatched with malicious payload | Per-action permission gates on every `platform.system_*` tool; tool definitions JSON-schema-validated | LOW |
| **R**epudiation | AI denies issuing a tool call | Every tool call logged to `Ai::AgentExecution` with full payload; full audit trail | LOW |
| **I**nfo disclosure | Tool returns cross-tenant data | Same scoping rules as the underlying controller — every tool dispatches through the regular service layer | LOW |
| **D**oS | AI loops on a destructive tool | `kill_switch_status` / `emergency_halt` MCP tools available; per-agent budget via `Ai::Autonomy::ConsentBudgetService`; `requires_approval` flag on dangerous skills | MEDIUM — autonomous loops are the entire reason `kill_switch_status` exists |
| **E**op | AI invokes a write-side tool without operator approval | `Ai::Skill.requires_approval = true` for destructive paths; UI surfaces approval modal | LOW |

### S5 — Internal CA / Vault

| Threat | Vector | Mitigation | Residual |
|---|---|---|---|
| **S**poofing | Forged Vault token | AppRole with bounded TTL; tokens not stored in env files | LOW |
| **T**ampering | Compromised CA mints a malicious cert | CA root key never leaves Vault; intermediate `pki_int` enforces role-bound issuance | LOW once mounted; **N/A today** (PKI not mounted in production — `LocalCaAdapter` is the only path live) |
| **R**epudiation | Operator denies issuing a cert | Vault audit logs (when audit backend mounted); platform-side `NodeCertificate` table | MEDIUM — Vault audit backend mount status varies |
| **I**nfo disclosure | Vault data exfiltration via leaked unseal keys | Shamir 3-of-5 today; auto-unseal target. Unseal keys split across operators and air-gapped media | LOW once auto-unseal lands |
| **D**oS | Vault sealed by accident | All Vault clients use `VaultUnavailableError` with circuit-breaker; degrades gracefully | LOW |
| **E**op | Server escalates from KV-only to PKI signing rights | AppRole policies scoped per use-case (KV read vs PKI sign) | LOW |

### S6 — Public mirror (GitHub `rett/powernode-system`)

| Threat | Vector | Mitigation | Residual |
|---|---|---|---|
| **S**poofing | Bad actor pushes to mirror | Push restricted to operator's GitHub account; main branch protected | LOW |
| **T**ampering | History rewrite on mirror | Force-push protected; LFS not used; mirror is `git push --mirror` from origin | LOW |
| **R**epudiation | — | N/A (read-only public) | — |
| **I**nfo disclosure | Internal IPs / hostnames / customer data leak via committed files | Pre-commit hook + `.gitleaks.toml` scan + this threat model itself documents defenses, not 0-days; review every commit before push | LOW once habit hardens |
| **D**oS | GitHub-side throttling | N/A — mirror is for visibility, not deployment | — |
| **E**op | Reader escalates to write | Public mirror is read-only; no auth scope to escalate from | — |

---

## 3. On-node Go agent

The agent runs as root (privileged), holds the node's mTLS certificate, can
mount overlays, can attach modules. Compromise of the agent is compromise of
the node.

| Threat | Mitigation |
|---|---|
| Stolen agent binary tampered + redeployed | Cosign-signed releases; fs-verity on the binary itself; kernel `lockdown=integrity` mode prevents unsigned kernel modules |
| Agent process exploited via module-supplied code | Per-module SELinux/AppArmor profile (F-19 ✅); capability dropping by default; modules without an explicit profile run default-deny (with operator override) |
| Agent log leak (token, CSR private key) | Private keys never written to logs (audit_session #6 enforcement); structured logging filters credential fields |
| Boot integrity compromise | Secure Boot chain end-to-end where firmware permits; UEFI signed kernel → signed initramfs → signed agent; QEMU thin slice optional but documented |
| Cloud metadata IMDS spoofing | Identity claim has fallback chain (IMDS → fw-cfg → local UUID); first success wins; certificate is bound to the claimed identity at enrollment so subsequent IMDS spoofing has no effect |

Agent-level threats and mitigations live in
`extensions/system/agent/internal/security/` — `mac.go` (MAC enforcement),
`policy.go` (default-deny), `capabilities.go` (cap dropping),
`egress.go` (network policy).

---

## 4. Cross-cutting concerns

### Supply chain (modules)

Every module ships as an OCI artifact in the platform's registry, signed via
**Sigstore Fulcio** (no long-lived signing keys; ephemeral OIDC-bound certs).
Per-module trust policy (`cosign_identity_regexp` + `cosign_issuer_regexp`)
pins each module to its expected publisher. The on-node agent verifies cosign
signatures BEFORE mounting; verification failure aborts the mount and emits a
`fleet_event` of kind `module.cosign_verification_failed` (CRITICAL).

Trust tiers:
- **internal** — signed by Powernode CI identity (auto-trusted)
- **verified-publisher** — signed by registered publisher's Sigstore identity
  (auto-trusted within publisher's namespace)
- **community** — signed but unverified author (operator approval required;
  flows through `SkillProposal` queue when the module ships skills)

### Secret material

| Class | Storage | Notes |
|---|---|---|
| Node mTLS private key | On-node (sealed via TPM where available); never leaves the node | CSR generated locally; signed cert returned by platform |
| Worker tokens | Vault KV; rotated on demand | Plain-text tokens never stored on workers in plain text |
| Per-account encryption key (active sweep P3) | Vault transit engine | Pepper applied via Vault transit; key never extracted to platform process memory in plain form |
| Provider connection access keys | Per-account Vault transit (active sweep P3 migration) | Today: Rails `encrypts`; sweep migrates to per-account pepper |
| Operator JWTs | Short-lived (1h); refresh tokens 30d | HttpOnly cookie + CSRF token |
| Bootstrap tokens | DB (SHA-256 hashed, not plaintext); 1-hour TTL; single-use; audit-logged | Generated by operator during enrollment flow |

### Idempotency

Currently NOT enforced on `POST /api/v1/system/tasks` — see
`system_review_and_plan.md §5 P0 #3` (open).

### Account cascade safety

Account `dependent: :destroy` cascades 17+ associations. Cloud resources
(actual EC2/GCE instances) are NOT terminated server-side — see
`system_review_and_plan.md §5 P0 #5` (open). Mitigation pending.

---

## 5. Active mitigations (in flight)

This stabilization sweep (May 2026) addresses several open items:

- **Per-account encryption keys** (P3) — Vault transit pepper for credentials
- **CloudSyncService scheduling** (P2.1) — closes drift detection gap
- **NodeModuleAssignment toggle** (P2.2) — enables per-(node, module) disable
  without destroying state
- **SBOM-aware CVE matching** (P4) — replaces v0 keyword stub with ecosystem
  version-range comparators
- **NodeInstance-as-Agent peer registration** (P6) — auto-registered peers
  start `enabled: false`; require operator activation before mention picker
  exposes them; remote task execution enforces operator's permission set

---

## 6. Runbook stubs

These are skeletons. Each will graduate into its own runbook under
`docs/system/runbooks/` as incidents drive the format.

### 6.1 Token leak

**Trigger:** suspected disclosure of a worker token, instance JWT, or
operator refresh token.

**First responder steps:**
1. Identify the token type from any leak indicator (claim format).
2. For worker tokens: `WorkerService.rotate_token(worker_id)` —
   immediately invalidates the leaked token. Then audit log.
3. For instance JWTs: revoke the `NodeCertificate` and force re-enrollment
   via bootstrap token flow; the instance must re-enroll within 24h or be
   marked decommissioned.
4. For operator refresh tokens: `User.invalidate_all_sessions(user_id)` —
   forces re-auth on all devices.
5. Audit Trail: search `FleetEvent.where("payload->>'token_jti' = ?", jti)`
   for blast-radius scope.

### 6.2 CA compromise

**Trigger:** suspected leak of intermediate CA private key (or worse, root).

**First responder steps:**
1. Issue a new intermediate from Vault PKI immediately; revoke the
   compromised intermediate.
2. Generate a CRL update; distribute to all reverse proxies + agents.
3. Force cert rotation across the entire fleet via
   `System::NodeCertificate.where(active: true).find_each(&:rotate!)` — each
   rotation forces an mTLS handshake with the new intermediate.
4. Audit any `node_certificate` issued by the compromised intermediate
   between known-good and breach detection times.
5. If root compromise: full PKI re-bootstrap. Hours of downtime; not
   recoverable without offsite key escrow.

### 6.3 Worker compromise

**Trigger:** worker process exhibits unauthorized behavior (e.g., dispatches
unexpected task, exfiltrates data, attempts to escape its scope).

**First responder steps:**
1. `WorkerService.disable!(worker_id)` — stops the worker from accepting new
   tasks.
2. Revoke its token + every other token issued to that operator, since the
   compromise vector may extend beyond one process.
3. Re-image the host (worker is meant to be ephemeral; treat any compromised
   worker as fully compromised).
4. Audit `task.events` for any tasks the worker handled in the past 30 days;
   re-validate their outputs against expected state.

### 6.4 Supply-chain failure (cosign verification fails)

**Trigger:** on-node agent reports `module.cosign_verification_failed` event
or a CI build fails cosign verification.

**First responder steps:**
1. Determine scope: single module + version, or whole publisher namespace?
2. If single module: revoke its `cosign_trust_policy` (set
   `cosign_identity_regexp` to `^$`); roll back affected nodes to the prior
   module version.
3. If publisher-wide: disable the entire publisher's trust tier in
   `extensions/system/server/db/seeds/module_trust_tiers.rb`; re-deploy.
4. Audit which modules are signed by the affected publisher; pull each from
   each fleet node.
5. Open an issue in the affected module's source repo (or alert the
   publisher via their stated security contact).

### 6.5 Vault unseal incident

**Trigger:** Vault sealed unexpectedly, or a Shamir share is suspected
compromised.

**First responder steps:**
1. Stop any in-flight operations that depend on Vault transit (per-account
   pepper) — gracefully degrades via `VaultUnavailableError` but provider
   credential decryption stops.
2. Convene Shamir share holders; perform unseal if availability is the issue.
3. If a share is compromised: rotate Shamir keys via
   `vault operator rekey -init -key-shares=5 -key-threshold=3`; redistribute.
4. Audit Vault access logs (when audit backend is mounted) for any operations
   between known-good and incident detection.
5. Post-incident: prioritize migration to auto-unseal (cloud KMS or HSM) to
   reduce future operator-availability risk.

---

## 7. Audit + reporting

- **Operator-visible audit:** Fleet Dashboard correlation chain viewer +
  ComplianceSnapshotService JSON export.
- **AI-driven anomaly detection:** `HoneypotAccessSensor` + `AttributeFailureExecutor`
  watch for suspicious patterns and auto-emit `fleet_event` rows of severity
  `critical`.
- **Knowledge base:** every confirmed/rejected operator decision feeds into
  compound learnings (Phase 1+ of platform AI evolution); recurring threats
  surface as patterns.

---

*References:*
- Active sweep plan: `~/.claude/plans/perform-comprehensive-examination-of-glistening-perlis.md`
- Golden Eclipse plan: `~/.claude/plans/we-are-working-on-golden-eclipse.md`
- System extension TASKS.md: `extensions/system/docs/TASKS.md`
- Architecture overview: `extensions/system/docs/ARCHITECTURE.md`
- Smoke test: `extensions/system/docs/SMOKE_TEST.md`
