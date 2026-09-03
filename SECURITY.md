# Security Policy

We take security seriously. This document covers two things a security reviewer needs: how to report a vulnerability and what to expect in response, and an honest summary of the platform's current security posture — each capability stated at its real maturity, with gaps conceded rather than glossed.

Powernode is maintained by a small team (effectively a solo maintainer today). The response-time targets below are set to be ones we can actually meet, not aspirational ones. Where a capability is partial or scaffolded, we say so — a posture summary that overstates reality is worse than useless to a buyer doing due diligence.

## Reporting a vulnerability

**Do not report security vulnerabilities through public GitHub issues, X (@nodealchemy), or any other public channel.** Public reports give attackers a window between disclosure and patch availability that we can't shorten.

**[Open a private security advisory on GitHub](https://github.com/nodealchemy/powernode-platform/security/advisories/new)** with:

- Description of the vulnerability + components affected
- Steps to reproduce (proof-of-concept welcome but not required)
- Impact assessment (data exposure, privilege escalation, denial of service, etc.)
- Your name + affiliation if you'd like attribution after the fix ships

You can expect:

- **Acknowledgment within 48 hours** of receipt (one maintainer; no 24/7 on-call — allow for time zones and weekends)
- A coordinated-disclosure timeline proposal within **5 business days**
- Status updates roughly weekly during active investigation, and promptly when the fix ships

If you don't hear back within 48 hours, please add a comment to the advisory (or open a fresh one) — notifications do occasionally get missed, and we'd rather hear about it twice than not at all.

## Coordinated disclosure

1. You report privately via a GitHub security advisory
2. We investigate, develop + verify a fix, and assign a CVE if warranted
3. We release the fix + publish a security advisory on the repo
4. You may publish your write-up after the advisory ships

We aim for a **90-day disclosure window** from initial report but can negotiate based on complexity. We won't pursue legal action against good-faith security research that follows this policy.

## Security posture

This section describes the platform's security-relevant capabilities so a reviewer can complete a first-pass vendor assessment from public sources. Each item carries an explicit maturity label:

- **Enforced** — implemented and actively gating the relevant operation; failure blocks the action.
- **Shipped** — implemented and in use, but advisory or operator-configurable rather than a hard gate.
- **Beta** — functional but still maturing; expect rough edges and changing interfaces.
- **Partial / do-not-rely** — scaffolding exists but the end-to-end guarantee is not yet in place. Do not assume it in a threat model.

Powernode runs in **core mode** (single-user self-hosted) when optional extensions aren't installed. Capabilities provided by an extension are noted as such — they apply only when that extension is mounted.

### Node identity & enrollment — mTLS (Enforced)

On-node agents enroll with the control plane over a bootstrap-token → mTLS-certificate exchange. The agent generates an Ed25519 keypair locally and the private key never leaves the node; only a CSR (carrying the public key) is transmitted. The control plane verifies its own TLS chain against a CA bundle the agent was provisioned with, and issues a node certificate via a Vault PKI backend (the CSR-signing flow never returns private key material). Issued certificates are rotated by the agent before expiry.

_Verified in:_ `extensions/system/agent/internal/enroll/csr.go` and `client.go` (keypair generation, CSR build, enroll exchange), `extensions/system/agent/internal/runtime/cert_rotation.go` (rotation), `server/app/services/security/vault_pki_client.rb` (Vault-PKI certificate issuance). Confirmed 2026-06-12.

### Boot-image verification — Sigstore/Fulcio keyless (Enforced)

Boot images (UKI) **are** cosign-verified before use, on every path, with no dev bypass. `CosignVerifier.VerifyBlob` is invoked directly in the boot-upgrade flow and refuses to run at all without a trust anchor — with neither a `KeyPath` nor identity/issuer pins configured it returns `"no KeyPath and no identity/issuer pins — refusing to verify without a trust anchor"` rather than passing.

_Verified in:_ `extensions/system/agent/internal/bootupgrade/bootupgrade.go:811` (CosignVerifier invoked on the boot blob), `extensions/system/agent/internal/verify/cosign.go:63-98` (`verify-blob` with identity/issuer pins; refuses without a trust anchor). Confirmed 2026-08-28.

### Module artifact verification — Sigstore/Fulcio keyless + fs-verity (Partial / do-not-rely)

**Correction (2026-08-28): a previous revision of this document labelled this capability "Enforced for module mounts". That was wrong, and this section previously overstated the guarantee. Both checks are implemented and fail-closed, but neither is currently wired into any path that mounts a module.** Reviewers assessing this platform should not assume module-mount signature verification today. The correction is recorded here rather than quietly edited, because the prior claim may already have been relied upon.

The two checks exist and are correct in isolation:

1. **Sigstore/Fulcio keyless signature verification** — `CosignVerifier` shells out to `cosign verify-blob` with pinned Fulcio certificate-identity and OIDC-issuer regexps, and refuses to verify without a trust anchor.
2. **fs-verity root-hash verification** — `FsVerifier` enables fs-verity on the pulled blob and asserts the on-disk Merkle root matches the hash the control plane published; if fs-verity is enabled but the module has no published root hash, the mount is refused rather than allowed through.

**What is actually wired on the module-mount paths:**

- All three reconciler construction sites pass `verify.AlwaysOK{}` — a `Verifier` whose `VerifyBlob` unconditionally `return nil`s — as the module verifier: the service loop (`internal/runtime/service.go:361`), the pivot composer (`internal/runtime/compose.go:611`), and CLI attach/update/sync (`cmd/powernode-agent/internal/cli/reconciler_factory.go:38`). `AlwaysOK` is labelled in its own source comment "NEVER use in production"; it is nevertheless the current default on these paths.
- `ReconcilerConfig.Fsverity` is **nil by default**, so the fs-verity gate is dormant — stated as such in the source at `internal/runtime/reconcile.go:934`.
- `CosignVerifier` is reachable from only two places: the boot-upgrade path above, and the operator-invoked `powernode-agent verify` CLI subcommand (`cmd/powernode-agent/internal/cli/verify_cmd.go:69`). Neither runs during a module mount.
- The gate at `internal/runtime/reconcile.go:926-944` is real and correctly fail-closed — it is simply handed a no-op verifier and a nil fs-verifier.

**Consequently the only integrity control actually applied to a module mount today is the sha256 blob digest** (`internal/oci/pull.go:229`), which is delivered by the control plane over the same channel as the blob itself. That detects corruption and truncation in transit; it does **not** establish provenance, and it does not survive a compromised or impersonated control plane.

Additional gaps, unchanged from the previous revision:

- The module-signing **publish pipeline does not yet emit signatures** for all artifact paths. This is the stated reason the verifier is stubbed: `extensions/system/agent/internal/runtime/service.go:344-347` — "Wired with `verify.AlwaysOK` as a Phase 1 development default … production deployments will swap in a real `CosignVerifier` once the M1 publish pipeline ships signatures."
- On-node **script execution does not yet verify cosign signatures** — that path currently requires an explicit `--allow-unsigned` dev flag and is **not** production-hardened. (`extensions/system/agent/cmd/powernode-agent/internal/cli/exec_cmd.go`: "cosign verification not yet implemented (use --allow-unsigned in dev only)".)
- **No Rekor / transparency-log inclusion check** is performed. We make no transparency-log claim. Keyless verification here means Fulcio-identity-pinned signature checking, not tlog-backed inclusion proofs.

_Verified in:_ `extensions/system/agent/internal/verify/cosign.go:46-108` (`CosignVerifier`; `AlwaysOK` at :101-108), `extensions/system/agent/internal/verify/fsverity.go` (enable + root-hash assertion), `extensions/system/agent/internal/runtime/reconcile.go:926-944` (the gate), and the three `AlwaysOK` call sites cited above. Re-confirmed by source review 2026-08-28.

### Read-only verified module filesystem — erofs + overlayfs (Enforced)

Each module is published as a single **erofs** (Enhanced Read-Only File System) image and loop-mounted read-only (`mount -t erofs -o loop,ro`); the union of attached modules forms the system root via overlayfs. erofs is read-only by design and integrates natively with fs-verity (see above), so module content is immutable on-node and integrity-checked. (An earlier composefs/squashfs path was removed when the project converged on erofs as the single canonical format — reviewers may see references to composefs in history; erofs is what ships.)

_Verified in:_ `extensions/system/agent/internal/mount/erofs.go` (read-only loop mount, canonical-format note), `extensions/system/agent/internal/mount/overlay.go`. Confirmed 2026-06-12.

### Software supply chain — SBOM + SLSA provenance + attestations (Shipped; supply-chain extension)

The supply-chain extension (`extensions/supply-chain/`, MIT, public) generates and stores software bills of materials and build-provenance attestations:

- **SBOM generation** across npm, RubyGems, pip, Maven, Go, and Cargo ecosystems, emitting **CycloneDX 1.5/1.6** and **SPDX 2.3**.
- **SLSA provenance** generation producing `slsa.dev/provenance/v1` (and v0.2) predicates, including provenance derived from pipeline runs.
- **Attestation** records (SLSA, in-toto), container image scan results, vulnerability correlation against CVE feeds, license compliance, and vendor risk scoring.

**Maturity caveat:** This is real, format-aware functionality, but treat it as **operational tooling for producing and tracking supply-chain artifacts**, not as a fully closed signing-and-enforcement loop. Attestation **signing** infrastructure exists (the `SupplyChain::SigningKey` model supports cosign / KMS / Vault key types), but the end-to-end chain that would let a consumer *cryptographically reject* an unsigned or mis-attested artifact at install time is still maturing and overlaps with the module-signing publish gap noted above. The extension is also optional — these capabilities are absent in a core-mode install without it.

**Additional caveat (2026-08-28):** the `SupplyChain::SigningKey` model's own sign/verify methods are **placeholders** — `sign_with_cosign`/`_kms`/`_gpg` return `nil` and `verify_cosign`/`_kms`/`_gpg` return `false` (`extensions/supply-chain/server/app/models/supply_chain/signing_key.rb:160-200`). Attestation signing is therefore modelled but not performed in-platform; do not read the presence of this model as a working signing path.

_Verified in:_ `extensions/supply-chain/server/app/services/supply_chain/sbom_generation_service.rb` (formats + ecosystems), `extensions/supply-chain/server/app/services/supply_chain/slsa_provenance_generator.rb` (SLSA predicate types), `extensions/supply-chain/server/app/models/supply_chain/{attestation,signing_key,build_provenance}.rb`. Paths corrected 2026-08-28 — these files live inside the `extensions/supply-chain/` submodule and a previous revision cited them under `server/`, where they do not exist. Mechanisms re-confirmed at the corrected paths.

### AI autonomy safety controls (Enforced / Shipped)

For deployments running autonomous agents, the platform ships layered controls:

- **Kill switch / emergency halt (Enforced).** A coordinated account-wide stop captures a state snapshot, then suspends new agentic work, cancels in-flight executions, pauses schedules, cancels queued agent-to-agent tasks, opens provider circuit breakers, demotes all agents to supervised, and drains AI job queues — recorded as an auditable event with restore metadata. _Verified in:_ `server/app/services/ai/autonomy/kill_switch_service.rb`.
- **Behavioral fingerprinting (Shipped).** Per-agent, per-metric statistical baselines (rolling-window mean/stddev) flag anomalous behavior via z-score deviation; sufficient observations are required before a baseline is trusted. This is **statistical anomaly detection**, not an ML/behavioral-biometrics model — set expectations accordingly. _Verified in:_ `server/app/services/ai/autonomy/behavioral_fingerprint_service.rb`, model `server/app/models/ai/behavioral_fingerprint.rb`.
- **Prompt-injection & input/output guardrails (Shipped).** A guardrails pipeline runs input rails (prompt-injection detection, PII detection, token-limit, topic/language restriction) and output rails. Prompt-injection and PII detection delegate to a fuller security service when an account context is present, with a pattern/heuristic fallback otherwise. **Maturity caveat:** detection is primarily **regex/pattern-based with confidence scoring** (with optional LLM-evaluator escalation for borderline cases) — it raises the bar against known injection and role-hijack patterns but is **not** a guaranteed defense against novel adversarial prompts. Treat it as defense-in-depth, not a hard boundary. _Verified in:_ `server/app/services/ai/guardrails/input_rail.rb`, `server/app/services/ai/security/agent_anomaly_detection_service.rb`.
- **Intervention policies, approval chains, and trust/quarantine (Shipped).** Operator-configurable intervention policies gate sensitive agent actions behind approval, agents carry trust scores that decay when idle, and rogue-behavior detection can emergency-demote and quarantine an agent. _Verified in:_ `server/app/services/ai/intervention_policy_service.rb`, `server/app/services/ai/autonomy/{approval_workflow_service,execution_gate_service}.rb`.

### Credential & key lifecycle — Vault-backed (Shipped)

Secrets and cryptographic material are managed through HashiCorp Vault rather than living in source or config:

- **KV secrets** via a circuit-breaker-protected Vault client (`Security::VaultClient`).
- **Transit encryption** (`Security::VaultTransitClient`) for application-layer encryption where Vault holds the key and never exposes plaintext key material — supporting encrypt/decrypt, key rotation, and key versioning (old versions still decrypt until explicitly retired).
- **PKI** (`Security::VaultPkiClient`) for issuing the node mTLS certificates described above.

As a project rule, key generation happens inside Vault (or a service that writes directly to Vault) — keys are never generated via ad-hoc CLI or stored in code. _Verified in:_ `server/app/services/security/{vault_client,vault_transit_client,vault_pki_client}.rb`. Confirmed 2026-06-12.

### Honest summary of gaps

For a reviewer's threat model, the most important concessions:

- Module **signature verification is not currently applied to module mounts at all** — the cosign and fs-verity gates are implemented and fail-closed but are wired with a no-op verifier and a nil fs-verifier on all three mount paths, leaving a control-plane-supplied sha256 digest as the only integrity check. Boot-image verification *is* enforced. The signing/publish pipeline and on-node script-exec verification are not yet shipped, and there is **no transparency-log (Rekor) check**. Do not assume a signed supply chain for module artifacts today. (This corrects a prior revision of this document, which described module-mount verification as Enforced.)
- Supply-chain SBOM/SLSA tooling is real and format-correct, but the **cryptographic reject-on-install enforcement loop is still maturing** and the extension is optional.
- AI guardrails are **pattern/heuristic-based defense-in-depth**, not a proof against novel prompt-injection.
- This is a **small-maintainer project**: there is no 24/7 security on-call and no paid bug bounty (see Acknowledgments).

We'd rather a reviewer find these stated plainly here than discover them mid-assessment.

## Scope

**In scope:**

- Rails API (`server/`) — authentication, permissions, multi-provider LLM routing, knowledge graph, RAG pipeline, MCP tool surface
- Sidekiq worker (`worker/`) — background job processing, scheduled jobs
- React/TypeScript frontend (`frontend/`) — operator UI and public marketing surface
- AI agent autonomy controls — kill switch, intervention policies, approval chains, behavioral fingerprinting, guardrails
- MCP server (`api/v1/mcp/`) — tool-action surface, session lifecycle
- On-node agent (`extensions/system/`) — enrollment/mTLS, module verification (cosign/fs-verity), read-only mount machinery, federation, SDWAN
- Supply-chain surface (`extensions/supply-chain/`) — SBOM integrity, attestation signing/verification, scan-result and vendor-risk integrity
- DevOps pipelines + step execution
- Stripe / PayPal payment processing where present
- Extension contract — the boundary between platform core and `extensions/*` submodules
- Vault credential lifecycle (storage, rotation, transit encryption, PKI)

**Out of scope:**

- Vulnerabilities in third-party dependencies — please report to the upstream project first; we'll address our exposure after the upstream fix is available
- Issues requiring physical access to a deployed server
- Theoretical attacks without practical exploitability
- Findings from automated scanners without manual verification
- Self-XSS or social-engineering-only attacks
- Misconfigurations of operator-controlled settings
- Capabilities explicitly labelled **Partial / do-not-rely** above, where we already acknowledge the gap — though a *bypass of a control we claim is Enforced* is firmly in scope and especially welcome

## Supported versions

| Version | Supported |
|---|---|
| `develop` branch | Active development; security fixes land here first |
| Most recent tagged release | Critical + high-severity fixes backported |
| Older tags | Please upgrade to the latest tag |

## Acknowledgments

Security researchers who responsibly disclose vulnerabilities through this process are credited in the resulting advisory unless they prefer anonymity. We don't currently run a paid bug bounty.

Per-extension security policies live in each extension's `SECURITY.md` (e.g., [extensions/system/SECURITY.md](extensions/system/SECURITY.md) covers the on-node agent, module supply chain, federation, and SDWAN surfaces; [extensions/supply-chain/SECURITY.md](extensions/supply-chain/SECURITY.md) covers SBOM integrity, attestation, and scan-result trust boundaries).
