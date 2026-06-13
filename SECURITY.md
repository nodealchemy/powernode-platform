# Security Policy

We take security seriously. This document covers two things a security reviewer needs: how to report a vulnerability and what to expect in response, and an honest summary of the platform's current security posture — each capability stated at its real maturity, with gaps conceded rather than glossed.

Powernode is maintained by a small team (effectively a solo maintainer today). The response-time targets below are set to be ones we can actually meet, not aspirational ones. Where a capability is partial or scaffolded, we say so — a posture summary that overstates reality is worse than useless to a buyer doing due diligence.

## Reporting a vulnerability

**Do not report security vulnerabilities through public GitHub issues, X (@nodealchemy), or any other public channel.** Public reports give attackers a window between disclosure and patch availability that we can't shorten.

Email **security@nodealchemy.com** with:

- Description of the vulnerability + components affected
- Steps to reproduce (proof-of-concept welcome but not required)
- Impact assessment (data exposure, privilege escalation, denial of service, etc.)
- Your name + affiliation if you'd like attribution after the fix ships

You can expect:

- **Acknowledgment within 48 hours** of receipt (one maintainer; no 24/7 on-call — allow for time zones and weekends)
- A coordinated-disclosure timeline proposal within **5 business days**
- Status updates roughly weekly during active investigation, and promptly when the fix ships

If you don't hear back within 48 hours, please re-send — mail does occasionally get filtered, and we'd rather hear about it twice than not at all.

## Coordinated disclosure

1. You report privately to security@nodealchemy.com
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

### Module artifact verification — Sigstore/Fulcio keyless + fs-verity (Enforced for module mounts)

Before the on-node agent mounts a platform module, it runs two cryptographic checks and refuses the mount if either fails:

1. **Sigstore/Fulcio keyless signature verification** — the agent shells out to `cosign verify-blob` with pinned Fulcio certificate-identity and OIDC-issuer regexps (the CI workflow's Actions OIDC identity). A signature that doesn't verify, or an identity that doesn't match the pin, blocks the mount.
2. **fs-verity root-hash verification** — the agent enables fs-verity on the pulled blob (making it read-only with Merkle-tree-backed integrity checks at open time) and asserts the on-disk root hash matches the digest the control plane recorded at build time. A mismatch blocks the mount.

**Important honesty caveat — verification is enforced; signing and transparency-log are not yet end-to-end.** What is enforced is *consumption-side verification* of module artifacts. The complementary pieces are **not** shipped and must not be assumed:

- The module-signing **publish pipeline does not yet emit signatures** for all artifact paths. Verification is wired to enforce once signatures are present; until the publish side ships them everywhere, coverage is incomplete. (`server/app/services/ai/.../service.go` comment: CosignVerifier to be wired "once the M1 publish pipeline ships signatures.")
- On-node **script execution does not yet verify cosign signatures** — that path currently requires an explicit `--allow-unsigned` dev flag and is **not** production-hardened. (`extensions/system/agent/cmd/powernode-agent/internal/cli/exec_cmd.go`: "cosign verification not yet implemented (use --allow-unsigned in dev only)".)
- **No Rekor / transparency-log inclusion check** is performed. We make no transparency-log claim. Keyless verification here means Fulcio-identity-pinned signature checking, not tlog-backed inclusion proofs.

_Verified in:_ `extensions/system/agent/internal/verify/cosign.go` (enforced `verify-blob` with identity/issuer pins; the `AlwaysOK` verifier is dev/test-only and labelled "NEVER use in production"), `extensions/system/agent/internal/verify/fsverity.go` (enable + root-hash assertion). Absence of Rekor/tlog and the signing/exec gaps confirmed by source grep 2026-06-12.

### Read-only verified module filesystem — erofs + overlayfs (Enforced)

Each module is published as a single **erofs** (Enhanced Read-Only File System) image and loop-mounted read-only (`mount -t erofs -o loop,ro`); the union of attached modules forms the system root via overlayfs. erofs is read-only by design and integrates natively with fs-verity (see above), so module content is immutable on-node and integrity-checked. (An earlier composefs/squashfs path was removed when the project converged on erofs as the single canonical format — reviewers may see references to composefs in history; erofs is what ships.)

_Verified in:_ `extensions/system/agent/internal/mount/erofs.go` (read-only loop mount, canonical-format note), `extensions/system/agent/internal/mount/overlay.go`. Confirmed 2026-06-12.

### Software supply chain — SBOM + SLSA provenance + attestations (Shipped; supply-chain extension)

The supply-chain extension (`extensions/supply-chain/`, MIT, public) generates and stores software bills of materials and build-provenance attestations:

- **SBOM generation** across npm, RubyGems, pip, Maven, Go, and Cargo ecosystems, emitting **CycloneDX 1.5/1.6** and **SPDX 2.3**.
- **SLSA provenance** generation producing `slsa.dev/provenance/v1` (and v0.2) predicates, including provenance derived from pipeline runs.
- **Attestation** records (SLSA, in-toto), container image scan results, vulnerability correlation against CVE feeds, license compliance, and vendor risk scoring.

**Maturity caveat:** This is real, format-aware functionality, but treat it as **operational tooling for producing and tracking supply-chain artifacts**, not as a fully closed signing-and-enforcement loop. Attestation **signing** infrastructure exists (the `SupplyChain::SigningKey` model supports cosign / KMS / Vault key types), but the end-to-end chain that would let a consumer *cryptographically reject* an unsigned or mis-attested artifact at install time is still maturing and overlaps with the module-signing publish gap noted above. The extension is also optional — these capabilities are absent in a core-mode install without it.

_Verified in:_ `server/app/services/supply_chain/sbom_generation_service.rb` (formats + ecosystems), `server/app/services/supply_chain/slsa_provenance_generator.rb` (SLSA predicate types), `server/app/models/supply_chain/{attestation,signing_key,build_provenance}.rb`. Confirmed 2026-06-12.

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

- Module **signature verification is enforced on the consume side**, but the **signing/publish pipeline and on-node script-exec verification are not yet fully shipped**, and there is **no transparency-log (Rekor) check**. Do not assume an end-to-end signed supply chain today.
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
