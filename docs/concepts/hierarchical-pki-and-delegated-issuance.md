# Hierarchical PKI and Delegated Issuance

**Status**: design / implementation plan — nothing here is implemented.
**Date**: 2026-08-26 (rev 5; revs 2–4 same day; rev 1 2026-08-25). Rev 3 fixed the first
critics' six showstoppers; a third critic reviewed rev 3's new material and confirmed S1/S3/S4
and the S2/S6 mechanisms sound as far as they went — then found the following, all incorporated
in rev 4:

1. **F1**: rev 3's identity-binding increment re-ran the S2 mistake through a different door —
   SAN-required verification and SAN-only authorization would have de-authenticated (and
   deadlocked, since re-enrollment itself authenticates over mTLS) every live SAN-less leaf.
   §7.2 now gates enforcement on a defined discriminator (*delegated* leaf = verified chain
   depth ≥ 3), with a quarantined CN arm deleted at cutover exactly like the legacy store read.
2. **F2**: the §4.4 anchor filter plus id-only SAN authorization silently widened node/worker/
   internal routes from "issued by us" to "issued anywhere in the tree" — breaking an invariant
   the codebase states verbatim (`traefik_config_writer.rb:114-115`) — and let a constrained
   subordinate mint working credentials for cousin subjects. §4.4 now defines **two trust
   scopes** (own-subject vs cousin-capable), and §7.2 authorization is **full-URI equality
   against a recorded identity URI**, never parse-and-resolve-by-id.
3. **F3**: rev 3's CRL ascent rode a heartbeat channel that does not exist (verified:
   `Federation::PeerClient` has no heartbeat method; the sweep is inbound-staleness only;
   outbound initiation is explicitly "a separate concern"). Ascent now rides the trust-bundle
   pull — which **does** exist and **is** scheduled (`worker/app/jobs/
   federation_trust_bundle_refresh_job.rb`) — upgraded to an exchange (§9.3).
4. **F4**: the relay bound was understated (`nextUpdate` is `cadence × safety_factor`, so the
   true bound is `safety_factor × cadence + grace`), and CRL ingest was unspecified — garbage
   ascents could fail-close a cousin subtree and signed replays could roll caches back. §9.3
   now specifies signature-verified, tree-membership-checked, strictly monotonic, bounded
   ingest, and restates the bound.
5. **F5/F6**: the §3.1 swap was not crash-safe (per-file rename ordering manufactured new
   DAMAGED states, no key↔cert check at load, no locking) and `pending/` lived on a default
   path that is volatile on overlay-rooted nodes. §3.1 now uses a version-dir + atomic symlink
   flip, load-time key↔cert assertion, single-writer locking, delivery key-match, abort-as-
   parent-revoke; §17 states the durability preconditions as *checked* preconditions.
6. **F7–F12**: legacy stores get an empty CRL at the revocation increment (the one legacy-dir
   write, acknowledged); cutover gains an explicit retired-anchors trust input (§11.2);
   revocation now lands **before** the subordinate verb and the verb itself demands an
   approval reference (§15); §4.4 gains a same-DN presented-chain retry and parse caps; §7.5's
   either-or now covers every SAN type with a loopback carve-out; §3.1/§5.3 state the no-PEM
   and boot-ordering postures.

Three **standing sections** added so these failure classes cannot recur silently: a
per-increment live-fleet impact table (§15.1 — would have caught S2, F1, F7, F8), a mechanism
inventory with a channel-exists column (§16 — would have caught S5, F3), and an
environment/durability precondition section (§17 — would have caught F6).

**Rev 5** applies the rev-4 critique's nine findings. The critic's verdict: rev 4 does not
repeat the rev-2/rev-3 pattern at the same severity, and no architectural change is warranted —
so rev 5 changes no structure. The two that needed design work: **F-1**, the containment class
relocated once more into `verify_request`'s **no-PEM forwarded-CN fallback**, whose own comment
states the premise ("our-CA-only") that a shared handshake anchor falsifies — closed by a
structural gate in §4.4 plus quarantined deletion (§12, §11.2); and **F-2**, the retired
cutover anchor had no CRL, so the F8 window would have failed closed against §9.3's own
posture — closed by a **terminal CRL** minted before the old key is set aside (§11.2). The
rest are accuracy and spec-tightening: the real exchange cadence is **hourly** and the bounds
are restated in hours (F-3, §9.3); the `inbound_subject` transition is specified (F-4, §7.2);
`identity_uri` recording semantics — uniqueness, absent-record refusal, record-before-deliver
atomicity, symmetric-peer scoping (F-5, §7.2); reader-side flip straddle and version-dir
pruning (F-6, §3.1); anchor-direct-leaf wording aligned across §4.4/§13 with §7.2 (F-7); two
§15.1 rows de-optimized (F-8); CRL ingest checks the issuer against current revocation state
(F-9, §9.3). A **fourth standing check** is added (§16.1): the backward premise sweep.

**Ask**: Powernode must be able to deploy a hierarchical PKI: a root authority that delegates
issuance to intermediate authorities, which delegate to further issuing authorities, which issue
leaf certificates to nodes. Arbitrary depth in principle; three or four tiers in practice. An
operator's deployment might look like `hub → regional hub → site hubs → nodes` — that topology is
an **illustration**, not a schema: every name, role, and parent in this design is declared by the
deploying operator, and anyone cloning the MIT repo can stand up their own tree with no reference
to any existing fleet, no shared trust anchor, and no phone-home.
**Companion**: [federated-identity-and-resource-sharing.md](federated-identity-and-resource-sharing.md)
(identity *across* trees; this doc is identity *within* one tree and how a tree is grown).
Deployment strategy for hubs is deliberately not presumed anywhere below (§18).

**Hard constraints honored throughout** (from CLAUDE.md + the operator):

1. **Vendor-neutral, publicly deployable.** No fleet-specific hostname, network range, or role
   name is encoded. Roles are abstract; a deployment declares its own role and parent.
2. **Crypto material safety is absolute.** A private key never leaves the host that generated
   it — CSR-only flows in every direction, including CA certificates. No key in logs, transport,
   or CLI. Vault-only storage where Vault exists; 0600-on-disk where it does not. Every
   issuance and revocation audited (the `AUDITED_ACTIONS` sink already exists).
3. **Core never depends on extensions.** Issuance stays in `extensions/system`; core only
   verifies, via the existing path-convention and injectable-provider seams (§14).
4. **Works in core mode and without Vault.** A Vault-less deployment can run a full hierarchy
   on the local adapter alone; a pure-core deployment (no extension) is unaffected.

---

## 1. What exists today (per-component verdict)

Every claim was verified against the tree on 2026-08-25/26; load-bearing ones show the command.
Line numbers reference the current `dev-loop/dev-improve` checkout. The deleted-vs-retained
ledger is §12; the mechanism/channel inventory is §16.

### 1.1 The CA itself — `System::InternalCaService` (extension, 567 lines)

| Component | What it does | Verdict |
|---|---|---|
| `LocalCaAdapter` | Ed25519 self-signed root, lazily generated, persisted to `POWERNODE_CA_LOCAL_DIR` (default `/var/lib/powernode/internal-ca`) as `root.key` 0600 / `root.crt` 0644 (`:232`, `:282-294`). Never rewrites an existing root; fails closed on a half-present pair (`:261-295`). **Best-effort persistence** (`:286-293`): an unwritable dir logs a warning and keeps an in-memory, per-process CA | **Reused and extended** — gains the chain-aware storage + state machine (§3) and a subordinate-issuance verb (§5). The `root.key`/`root.crt` **names** are removal targets (deleted by the final increment, after cutover — §11); the never-rewrite / fail-closed **discipline** is retained (§12). The in-memory fallback is a **removal target**: issuance from an unpersisted CA refuses (§12). Note the **default path is not durable on overlay-rooted nodes** — a §17 precondition, not an assumption |
| `VaultCaAdapter` | Delegates to `Security::VaultPkiClient` (core): `sign`, `revoke`, `root_certificate_pem` (reads `/ca/pem` — one cert) — and nothing else | **Reused; needs at least THREE new client verbs**: `sign_intermediate`, `set_signed`/chain install, chain-aware bundle fetch (`/ca_chain`) plus CRL fetch — without the chain fetch, `anchor_fingerprint` on a Vault subordinate misreports the intermediate as the tree identity. Offline-**unprovable** (WebMock replays our fixtures); named live-smoke item (§15) |
| `issue_certificate` | Hardcodes `basicConstraints CA:FALSE` critical (`:315`), `keyUsage digitalSignature, keyEncipherment`, `extendedKeyUsage clientAuth, serverAuth` | **Kept as the leaf-only path** — structurally incapable of minting a CA (§5.2). Gains: stamping the CA-constructed URI SAN (§7.2) and recording the identity URI on the subject row |
| `build_self_signed_root` (`:372`) | The ONLY `CA:TRUE` in the codebase: no pathlen, 10-year life, serial 1, `keyUsage keyCertSign, cRLSign` | **Extended** — anchors gain configurable pathlen (§6), random serial, identity namespace, empty CRL at birth (§9); parameters from process environment (§3.1). Existing anchors re-minted by §11 |
| `ca_chain_pem` (local `:337`) | One cert | **Semantics change** — full chain (§4); one cert stays the anchor's degenerate case |
| `root_cert` (`:130`) | Parses the FIRST cert only | **Removal target** — zero callers anywhere including specs (verified below); deleted, no alias |
| `revoke` (local `:366`) | `{ ok: true, mode: "local-noop", serial: }` — a no-op | **Removal target** — replaced by real CRL-backed revocation, P0 (§9) |
| `new_root_subject` | `O=Powernode`, `OU=<per-CA random UUID>`, `CN=<prefix> <host identity>`; identity of record is `Security::CaFingerprint`, never the DN | **Retained and re-justified** (§12) |

```
$ grep -n 'CA:TRUE\|CA:FALSE' extensions/system/server/app/services/system/internal_ca_service.rb
315:        cert.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
383:        cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))

$ grep -rn "root_cert" server extensions/system --include=*.rb | grep -v vendor | grep -v "def root_cert"
(no output — zero callers, including specs)

$ grep -n "def " server/app/services/security/vault_pki_client.rb
36: def sign(...)   58: def revoke(...)   76: def root_certificate_pem   90: def role_config
```

### 1.2 Verification and trust distribution

| Component | What it does | Verdict |
|---|---|---|
| `Security::MtlsClientVerifier` (core) | Anchors flat-mapped into an `X509::Store` as **trusted** (`:106-108`); `verify` parses **one** cert (`:78`), `StoreContext.new(store, leaf)` with **no untrusted-chain argument** (`:125`); per-root retry on same-DN anchor collisions (`:87-99`) | **Cannot build a path through presented intermediates** (measured: intermediate-issued leaf fails against anchors `[root]`). §4.4 adds path-building — in the **cousin-capable scope only** (F2). The per-root anchor retry is retained (§12) and gains a presented-chain analogue (F10, §4.4) |
| `Security::MtlsTrust` (core) | `verify_request` passes `anchors: [own_ca_pem]` (`:74`); `own_ca_provider` set at boot by the extension engine (`powernode_system/engine.rb:162`; a raise is rescued to nil at `:36-39` — fail-closed hub-wide); `forwarded_pem` (`:154`) keeps only the first comma-joined element, discarding Traefik's forwarded chain; the **no-PEM fallback** (`:80-83`) trusts the forwarded subject CN on the stated premise — verbatim — that "Traefik's own chain-check against **our-CA-only** is authoritative" | **Changes in §4.4, per scope**: own-subject routes keep own-chain-only trust with **no** foreign path-building (preserving the stated invariant at `traefik_config_writer.rb:114-115`: peer/tree-signed certs are "rejected on node/worker routes — MtlsTrust verifies against our CA only"); the federation route gains anchor + presented-chain verification. The parser keeps every forwarded element (per-element parse preserves the split's original defensive purpose). The no-PEM fallback's premise is exactly what a shared handshake anchor falsifies (F-1) — gated structurally in §4.4, deleted with the other quarantined arms (§12) |
| `Core::IngressConfigWriter` | Sources `ca-chain.crt` + `root.crt`; per-block SHA-256 dedup; degrades per-source, never nils; **drops** unparseable blocks (`:661-663`) | **Changes**: +`chain.crt` source; the §8.1 anchor filter for handshake bundles. Dedup + never-nil retained (§12) |
| `Acme::TraefikConfigWriter` (extension) | `internal-ca.pem` (MtlsTrust anchor input) + `client-auth-bundle.pem` (ours + peer anchors, fingerprint-deduped); **keeps** unparseable anchors by documented intent (`:128-129`) | **Changes**: anchor filter for the handshake bundle; unparseable posture unified (§12). `.crt`/`.pem` split is three files, three consumers (§4.3) |
| `FederationApi::TrustBundleController` | Serves `ca_chain_pem` over mTLS | **Extended** — becomes the CRL **exchange** endpoint (§9.3) |
| `Federation::TrustBundleRefreshService` | Pulls each symmetric peer's bundle; **scope = `where.not(trusted_ca_pem: [nil,""])`** (`:56`); **scheduled** — worker-dispatched via `worker/app/jobs/federation_trust_bundle_refresh_job.rb` → `worker_api/federation_trust_bundle_controller` (the channel exists AND runs; §16) | **Generalized**: source sets keyed on explicit relationship predicates (parent via `parent_peer`; symmetric via `peer_kind: "platform"` + spawn fields) — never column presence, which under §11.3 excludes the parent by construction. Gains the exchange payload (§9.3) |
| **Outbound peer heartbeat** | `FederationApi::HeartbeatController` exists **with zero callers repo-wide**; `Federation::PeerClient` exposes `fetch_catalog`, `fetch_trust_bundle`, `post_subscription`, `delete_subscription` — **no heartbeat**; `system/federation/heartbeat_sweep_service.rb` marks stale peers degraded and states outbound initiation is "a separate concern" | **Does not exist and is not relied on** (F3 — rev 3 leaned on it; rev 4 does not). Listed in §16 so no future rev leans on it unawares |

### 1.3 The federation/peer layer — where "hierarchical" is currently a misnomer

| Component | What it does | Verdict |
|---|---|---|
| `System::FederationPeer` | `SPAWN_MODES = %w[managed_child autonomous_peer cluster_member out_of_band]` (`:29` — the spawn service's own list omits `out_of_band`); `SPAWN_ROLES` with a real `spawn_role` column (baseline migration `:302`; validations `:98`, `:115`); `parent_peer_id` self-FK; status lifecycle; `trusted_ca_pems` (`:159`) + the flat-child comment (`:152-154`) | Topology model **reused as the tree's registry** (§5). The flat-child nil convention + comment are removal targets (§11.3, readers enumerated there). Today a `managed_child` is a **leaf**, not a CA |
| `FederationAcceptanceService#sign_federation_csr!` | Signs the child's CSR **as a leaf** off our CA, CN forced to `fed:<peer.id>`; cert + chain in-band; key never travels | **Template for §5** — transport, token auth, identity-assignment, key-safety all reused |
| `Federation::OutboundIdentityService` | Child-side keypair + CSR in-process; key sealed to Vault-backed storage | **Pattern for §5.1** |
| `System::NodeCertificate` | `serial` unique, `revoked_at`, `subject_kind`; `active` enforced on NodeApi auth (`base_controller.rb:69`) | **Reused** — gains `subject_kind: "subordinate_ca"` |
| `System::SpawnPlatformService` | Peer row + acceptance token; `DEFAULT_TOKEN_TTL = 7.days.to_i` (`:40`; the adjacent "minutes-to-hours" comment is wrong) | **Reused** — §5.3 treats gate 1 as week-scale/weak; CA-capable spawns shorten the TTL (config) |
| `Ai::ApprovalRequest` (core) | `belongs_to :approval_chain` — **required** (`:9`); all `on_approval_decision` implementors are core; `AutonomyGate` fallback `approvers: ["*"]` | **Not turnkey** — §5.3 specifies the extension-side source, permission-scoped chain, boot-ensure |
| `CloudSeed#resolve_ca_pem` (`:143-156`) | Rescues ANY adapter error into a literal `FIXTURE-fallback` PEM string seeded to provisioned VMs | **Removal target** (defect): fixed in increment 1 to fail loudly |

### 1.4 Verified premise: there is no installed base — the license for the clean model

Read-only production query (2026-08-25): `federation_partners` = 0, `system_federation_peers`
= 0, `system_federation_grants` = 0; and no sub-CA issuance path exists in code, so no
deployment can hold a subordinate CA. **Nothing to grandfather — but this licenses the *end
state*, not the *sequencing*** (S2, F1): live development hubs hold `root.key`/`root.crt`,
serve mTLS off them via `engine.rb:162`, and every live leaf is a SAN-less depth-1 cert.
Every enforcement flip in this design is therefore either impact-free on that population by
construction, or explicitly sequenced behind the §11 cutover — audited per increment in
§15.1. Re-verify the zero counts before the ceremony increment.

---

## 2. Assumptions (numbered, explicit)

1. **Ed25519 end-to-end** — existing choice; both verifier stacks handle Ed25519 chains and
   CRLs (measured); depth>1 exercised in-process by increment 1.
2. **TLS clients can present their full chain; Traefik forwards it** (one block per peer
   certificate, comma-joined — verified in `mtls_trust.rb:144-155`). The §4.4 parser stops
   discarding it. Residual: Traefik *accepting* a chain-presenting client against an
   anchors-only caFile at the handshake — the one link offline tests cannot prove (§19 Q5).
3. **The DB is not dependably reachable at CA-load time** (stated in the service).
   Consequences: role derivable from CA-store files alone (§3); anchor-generation parameters
   from process environment (§3.1); boot-time ensures rescue-and-retry (§5.3).
4. **Traefik cannot enforce CRLs at the handshake**; app layer is authoritative (§9.4).
   OpenSSL hard-fails at `nextUpdate` — the grace window is app-owned cache logic (§9.3).
5. **No installed base** (§1.4) — end-state license only; sequencing audited in §15.1.
6. **Durability is a precondition, not an assumption** — §17. The CA store (including
   `pending/`) must live on storage that survives reboot; on overlay-rooted nodes the shipped
   default path does not, and §17 says what checks and what fails.

---

## 3. Role model: role is a property of the CA material, not a config value

Unchanged in principle from rev 3: **anchor** = self-signed `ca.crt`; **subordinate** =
parent-issued `ca.crt` + `chain.crt`; role emergent from material, established by the §5
ceremony; no role env var; no tier names in code. Adapter shape: extend the two adapters with
three verbs (`issue_subordinate_certificate` — which now **requires an
`approval_request_id`** and refuses without one, the adapter-level residual of gate 3 (F9);
`subordinate_csr`; `crl_pem` + real `revoke`).

`LocalCaAdapter` storage layout (rev 4 — version-dir, for F5's atomicity):

```
<POWERNODE_CA_LOCAL_DIR>/
  live -> versions/<id>/          atomic symlink; the ONLY thing the loader follows
  versions/<id>/ca.key    0600
  versions/<id>/ca.crt    0644    self-signed OR parent-issued
  versions/<id>/chain.crt 0644    ca.crt + ancestors incl. anchor
  crl.pem                 0644    this CA's current CRL — present from birth
  retired-anchors.crt     0644    optional, cutover window only (§11.2, F8)
  pending/                        staged enrollment material — never read as live
  .lock                           flock for every mutating operation
```

Legacy `root.key`/`root.crt` are read (as an anchor, one-cert chain) until the final increment
deletes the fallback after the operator cutover — the S2 sequencing, unchanged from rev 3.

### 3.1 The CA-store state machine (S6, hardened per F5/F6/F12)

| State | On disk | Adapter behavior |
|---|---|---|
| **EMPTY** | nothing (and no legacy pair) | Lazy anchor generation permitted — under the flock, re-checked after acquiring it (closes the TOCTOU race), and **suppressed** if `pending/` exists |
| **ENROLLING** | `pending/`, no `live` | Lazy generation suppressed; issuance verbs refuse ("enrollment pending <id>"); verification surfaces return the nil posture. The no-PEM concern (F12a) is inert here **for a stated reason, not by luck**: with no CA there is no clientAuth caFile, Traefik negotiates no client cert, `passTLSClientCert` sets no header, and the unconditional strip middleware has already deleted any client-supplied one — so the forwarded-CN fallback has nothing to trust |
| **ACTIVE-ANCHOR** / **ACTIVE-SUBORDINATE** | `live` → complete version dir | Full service. **Every load asserts key↔cert match** (public-key comparison) — mismatch is DAMAGED, refusing service rather than silently signing unverifiable certs (F5b) |
| **RE-ENROLLING** | `live` + `pending/` | Live CA serves; staged material inert until flip |
| **DAMAGED** | half-present pair, or key↔cert mismatch | Fail closed; operator intervention |

Mechanics (F5):

- **Single writer**: every mutating operation (staging, generation, flip, abort) holds
  `flock(<dir>/.lock)`; concurrent stagers and racing crash-recovery are serialized out.
  **Readers** (F-6): `flock` covers writers only, so a reader resolving `live` per-file can
  straddle a flip and trip the key↔cert assertion spuriously (a transient false DAMAGED —
  an availability blip and a false alarm, not a compromise). Loaders therefore resolve the
  symlink **once** via `readlink` and open every file through the resolved version dir;
  retry-once-on-mismatch is the belt over that.
- **Version-dir pruning** (F-6): a crash after a first-generation version dir completes but
  before the flip reads as EMPTY, so the next generation orphans a complete dir holding an
  unused private key. Policy, stated: at load, under the lock, any version dir that is
  neither the `live` target nor the in-flight staging is deleted after a configurable age —
  safe by the same argument as staged-key abort (nothing was ever issued off an unreferenced
  key). The previous `live` target is retained for one generation (rollback aid), then falls
  under the same rule.
- **Staging**: `subordinate_csr` writes key + CSR into `pending/` only; the live store is
  untouched for the whole approval window.
- **Completion**: delivered cert's **public key must match the staged key** (F5d) — mismatch
  refuses and alarms. Then the complete version dir is assembled (key, cert, chain), each file
  fsynced, the version dir fsynced, and `live` is flipped by atomic symlink rename, followed
  by a **parent-directory fsync** (F6 — rename durability across power loss is otherwise not
  guaranteed). A crash at any point leaves either the old `live` intact or the new one
  complete; there is no ordering window in which a mismatched or partial pair is live, and no
  new DAMAGED states are reachable by power loss.
- **Abort/retry**: abort (under the lock) deletes `pending/` — the staged key is destroyed,
  never reused; retry stages a fresh key (safe: nothing was issued off it — the deliberate
  exception to never-rewrite, §12). **Abort propagates to the parent** (F5d): the child
  notifies via the enrollment endpoint, and the parent **revokes** any already-approved
  cert for the destroyed key (registry + CRL); an approved-but-never-collected cert also
  auto-revokes after a configurable collection deadline, so no CA:TRUE cert for a dead key
  stays live either way.
- **Loss detection** (F6): the ceremony also exists as a DB row
  (`System::SubordinateCaRequest`, §5.3), so a reboot that erases `pending/` on
  non-durable storage is *detected* — the reconcile sees an in-flight request with no staged
  material, alarms, keeps lazy generation suppressed (DB-side, once the DB is up), and
  the operator retries. This is detection, not prevention: prevention is §17's durable-path
  precondition. The pre-DB boot window (assumption 3) is covered by the on-disk `pending/`
  marker when storage held, and by the EMPTY + suppressed-only-by-disk residual when it did
  not — stated plainly in §17.
- **Anchor generation parameters**: from process environment (`POWERNODE_CA_PATHLEN`,
  `POWERNODE_CA_IDENTITY_NAMESPACE`, …), readable wherever lazy generation can fire;
  DB-backed settings only at ceremony time (post-boot, operator-facing).

---

## 4. Chain representation: `ca_chain_pem` becomes a chain

### 4.1 The new contract

Full chain, issuing CA first, anchor last; one cert for an anchor. `ca_fingerprint` (issuing —
"who signs here") and `anchor_fingerprint` (terminal self-signed — "which tree"); equal on a
flat deployment; `CaFingerprint` stays the identity of record. On Vault, `anchor_fingerprint`
requires the chain-aware fetch (§1.1).

### 4.2 Every depth-1 caller, and what each becomes

| Caller | Depth-1 assumption | Disposition |
|---|---|---|
| `root_cert` (`:130`) | First cert only | **Deleted** — zero callers incl. specs; replaced by `issuing_cert` / `anchor_cert` |
| `LocalCaAdapter#ca_chain_pem` | One cert | Returns `chain.crt` |
| `ca_fingerprint` call sites | Singular CA | Keep meaning; preflight/diagnostics add `anchor_fingerprint` + chain length |
| `client_auth_ca_sources` (`:644`) | `root.crt` | +`chain.crt`; `root.crt` deleted with the layout in the final increment |
| `prepare_client_auth_ca` / `dedupe_anchors` | — | Multi-cert-safe already; both gain the §8.1 anchor filter; unparseable postures unified (§12) |
| `TrustBundleController` | Serves the single cert | Serves the chain; becomes the CRL exchange (§9.3) |
| `FederationPeer#trusted_ca_pem` | One anchor per symmetric peer | Full chain; nil convention deleted (§11.3) |
| `MtlsTrust` / `MtlsClientVerifier` | Anchors = whole trust input; presented chains discarded | **Changed per scope — §4.4** |

**The remaining call sites, classified individually.** Rev 5 swept these into one
"pass-through" row — and that catch-all is exactly how a real depth-1 assumption hid
(`parse_issuer`, below). There are **14 `ca_chain_pem` call sites** in the tree; the eight
not already dispositioned above:

| Call site | What it does with the value | Disposition |
|---|---|---|
| `node_api/enrollment_controller.rb:39`, `enrollment_refresh_controller.rb:37` | Response pass-through to the enrolling agent | Unchanged code; the response **now carries a chain** — which is the §8.2 requirement (the agent must persist and present it), not a side effect |
| `concerns/system/runtime_handshake_handlers.rb:52` | Pass-through in the runtime handshake payload | Same: carries a chain; consumer is a §8.2 holder |
| `federation/outbound_identity_service.rb:54,69,97` | Stores into the Vault-backed credentials blob alongside cert + key | Unchanged; the stored blob now holds a chain, which `PeerClient` must present (§8.2) |
| `federation/peer_trust_service.rb:39` | `ca_bundle_pem:` in the symmetric trust-exchange payload | Unchanged; a symmetric peer now receives (and stores in `trusted_ca_pem`) our full chain — already specified in this table's `trusted_ca_pem` row |
| `system/federation/federation_acceptance_service.rb:223` | Pass-through in the accept response | Unchanged; carries a chain |
| `system/docker_daemon_provisioner_service.rb:183` | Stores `ca_chain_pem:` into the managed-host TLS credential hash | Unchanged code; see the api_client row for the consumer-side consequence |
| `devops/docker/api_client.rb:468` | **Core** — reads the *stored credential hash key* `"ca_chain_pem"` (a JSON string key, **not** the extension service — core purity is intact and a future reader should not mistake this for a core→extension dependency) and feeds it to Docker's `ca_cert` | Docker's TLS layer is Go: `x509.CertPool` loads **every** cert in a PEM bundle, so a chain here is accepted and verification of the daemon's server cert proceeds through it — intended and safe, with the standard pool-trusted-intermediate caveat already covered by §9.4's CRL checking on our side. Byte-identical today (one cert) |
| `system/node_enrollment_service.rb:70` → `parse_issuer` (`:170-176`) | **NOT a pass-through**: `OpenSSL::X509::Certificate.new(ca_chain_pem).subject.to_s` — **first cert only** — persisted as `issuer_subject` on the `NodeCertificate` row. The same depth-1 parse this design deletes `root_cert` for, in a second location the rev-5 table never named; under §4.1's contract its referent would silently shift from "the anchor's subject" to "the issuing CA's subject" **on a persisted attribute** — the class §16.1 sweeps for | **Semantic chosen deliberately** (increment 1): `issuer_subject` means **the leaf's own issuer DN** — the issuing CA — and is derived from `issued[:cert_pem]`'s `.issuer`, not by parsing the chain at all. That is what a field named `issuer_subject` should mean, it is byte-identical for every existing row (at depth 1 the issuing CA *is* the anchor, so no data migration and no referent change for persisted values), it is correct at any depth, and it cannot be broken by chain-ordering mistakes. The field stays diagnostic — `CaFingerprint` remains the identity of record (§4.1); the column comment is updated to say both |

(The other six of the 14: `trust_bundle_controller`, `traefik_config_writer` ×2,
`engine.rb:162`'s provider wiring, `internal_ca_service` itself, and `cloud_seed.rb` — all
dispositioned above / in §1.2–§1.3.)

### 4.3 The `.crt` / `.pem` filename split, reconciled

Three files, three consumers (core host-login `internal-ca.crt`; extension `internal-ca.pem`
and `client-auth-bundle.pem`); increment 1 cross-references them at each write site.

### 4.4 The core verifier learns to build a path — in two distinct trust scopes (S1 + F2a)

Measured baseline: a leaf issued by an intermediate fails against anchors `[root]` — the
verifier consults no presented chain and the header parser discards it. But fixing that
uniformly, as rev 3 did, breaks an invariant the codebase states verbatim
(`traefik_config_writer.rb:114-115`): peer- or tree-signed certs must be "rejected on
node/worker routes — `Security::MtlsTrust` verifies against our CA only". Rev 3's
anchor-filtered `own_ca_pem` would have silently converted every own-subject route from
"issued by US" to "issued anywhere in the TREE". Rev 4 therefore defines **two scopes with
different trust inputs**, and the widening exists only where cross-branch verification is the
point:

| Scope | Routes | Trust input | Presented-chain path building |
|---|---|---|---|
| **Own-subject** | node / worker / internal / cable (`verify_request`, `anchors: [own_ca_pem]` — `mtls_trust.rb:74`) | Our own `chain.crt`, as today | **NO** — a cousin's or descendant's leaf must keep failing here. Residual, stated precisely (F-7, aligned with §7.2): leaves issued directly by an **intermediate ancestor** chain-verify here (its CA is in our chain) and build chain-length ≥ 3 — *delegated*, so §7.2's rules 2/3 do bind them (full-URI match against locally recorded identities, which they won't have → refused). The genuinely unchecked residual is **anchor-direct leaves** (chain-length 2, non-delegated — measured): they ride the CN arm until the final increment, bounded only by "only the anchor hub can mint chain-length-2", which is the §13 malicious-parent bound restated, not something stronger |
| **Cousin-capable** | the federation route only (`verify_request_against`, per-peer / tree binding — `federation_api/base_controller.rb:57`) | Tree **anchor** only (`anchor_cert`) | **YES** — leaf + presented intermediates build to the anchor; this is what makes a cousin's inbound call verify (§11.3) |

Mechanics shared by both scopes:

- `MtlsTrust#forwarded_pem` → `forwarded_pems`: parse **every** comma-joined element
  per-element (preserving the original split's defensive purpose); first = leaf, rest =
  presented chain. **Parse caps** (F10): at most `POWERNODE_MTLS_MAX_CHAIN` elements
  (default 8, config); overflow refuses.
- `MtlsClientVerifier.verify(cert_pem:, anchors:, presented_chain: [])`: anchors trusted in
  the store; presented intermediates passed as `StoreContext.new(store, leaf, chain)` —
  untrusted path material, conferring no trust.
- **Same-DN presented-chain retry** (F10, measured): OpenSSL takes the first same-DN
  candidate in the untrusted chain and does not recover — `[forged-same-DN-int,
  genuine-int]` fails even with the genuine cert present, a shape §10.2 re-key overlap plus
  §8.2 concatenation can produce legitimately. On failure with same-DN duplicates present,
  retry with each same-DN candidate isolated (the presented-chain analogue of the anchor
  retry §12 retains). Bounded by the parse cap.
- Handshake bundles (`caFiles`) are **anchors-only** via the §8.1 filter — a proxy-layer
  statement; the backend re-binds per scope above **on the PEM path**. Rev 4 claimed no
  backend decision rests on the handshake widening; that was false for one branch:
- **The no-PEM fallback is gated structurally** (F-1). `verify_request`'s no-PEM branch
  (`mtls_trust.rb:80-83`) trusts the forwarded subject CN on a premise its own comment states
  verbatim: with no peer CAs in the bundle, "Traefik's own chain-check against **our-CA-only**
  is authoritative". The moment the handshake bundle carries a **shared** anchor — a
  subordinate enrolling (its bundle then holds the tree anchor), or cutover step 3 — that
  premise is false: the handshake accepts every tree member's leaves, and any route still
  served without a forwarded PEM would authenticate a cousin's or descendant's cert as
  whatever CN it carries, with no chain for rules 2/3 to discriminate on (Traefik forwards
  `subject.commonName` only — `ingress_config_writer.rb:557-560`). The existing partial
  mitigation is real but contingent: core-written routers attach `pem: true` whenever
  clientAuth is active (`:461-462`, `:553-562`), leaving what the code itself calls "routes
  fronted by an ingress core did not write" (`:541-544`). The design closes it rather than
  inheriting it: **the no-PEM branch refuses whenever the deployment's trust material is
  tree-shaped** — own chain length > 1, or `retired-anchors.crt` present — i.e. the branch
  survives only where its stated premise still holds (a flat, anchor-only deployment), a
  derivable, attacker-uninfluenceable gate that ships with this increment and is inert on
  today's fleet. The writers extend the existing peer-CA↔pem-forwarding coupling to tree
  anchors (any bundle carrying an anchor beyond the hub's own issuing CA forwards PEMs), and
  the branch itself is quarantined like the other legacy arms and **deleted in the final
  increment** (§12), the cutover flipping the whole fleet through the gate at step 3 (§11.2).

Proving oracles: the S1 killer (request spec, comma-joined header, intermediate-issued leaf,
anchors-only → passes on the federation scope, **refused on a node route**); the F-1 gate
(no-PEM request against a flat trust input → CN fallback as today; same request once
`retired-anchors.crt` exists or the chain deepens → refused); the negative
(no presented chain → refused); the F10 mutant chain; bare-leaf depth-1 byte-identical.

---

## 5. Subordinate enrollment: the ceremony that mints an intermediate

Principle unchanged: **leaf issuance is automatic; CA issuance is never automatic.**

### 5.1 Child side

Fresh Ed25519 key staged into `pending/` under the lock (§3.1), 0600 (or Vault
`generate/internal`); only the CSR leaves. Never CLI, never logged, never transported.

### 5.2 Parent side — what gets stamped

The parent ignores every CSR attribute and extension and stamps its own: `CA:TRUE,
pathlen:<budget>` critical (§6); `keyUsage keyCertSign, cRLSign` critical; parent-assigned
subject; `nameConstraints` per §7; operator-set TTL; random serial; registry row (§9.1) with
the `approval_request_id`. **Post-issuance self-verify, mandatory**: throwaway-leaf probe
matrix through the would-be chain — signatures, validity, pathlen, constraints, including the
S4 probes (hostname-shaped CNs inside/outside any DNS scope) and per-SAN-type probes for the
declared scopes (§7.5). A wrong constraint issues nothing.

### 5.3 Authentication and the approval gate

Three gates: (1) channel — acceptance token (**7-day** default TTL, treated as weak;
CA-capable spawns pass a shorter TTL via the existing override) or established peer mTLS;
(2) an operator-created/accepted peer row; (3) **explicit operator approval, every time** —
`System::SubordinateCaRequest` (the first extension-side approval source) implementing
`on_approval_decision`; a chain bound to a code-defined `system.ca.delegate` permission
(never `"*"`), `timeout_action: deny`; **ensured idempotently after boot** — the ensure runs
in a post-boot hook with rescue-and-retry, never in the CA-load path, so it cannot collide
with assumption 3 (F12b): its only consumers are ceremony endpoints, which need the DB
anyway. The request row doubles as the §3.1 loss-detection record. No auto-approve, no batch.
Gate 3 is additionally enforced at the adapter surface: `issue_subordinate_certificate`
refuses without an `approval_request_id` (F9).

### 5.4 Transport, delivery, renewal, re-key

Accept-flow `subordinate_ca_csr_pem` (distinct from the leaf `csr_pem`) + mTLS
`federation_api/subordinate_enrollment` for elevation; `{status: "pending_approval",
request_id:}` then polling. Delivery: public material only; completion runs the §3.1
key-match + atomic flip. Renewal (same key, same constraints): proof-of-possession over
mTLS, auto-approvable in a configured window. Re-key or constraint change: full ceremony,
RE-ENROLLING staging. Abort: §3.1 — including the parent-side revoke.

### 5.5 Registry on the parent

`NodeCertificate` (`subject_kind: "subordinate_ca"`) + registry row (§9.1);
`FederationPeer#subordinate_ca_serial`.

---

## 6. Depth and pathlen: the delegation budget

Anchors carry `CA:TRUE, pathlen:<n>` from `POWERNODE_CA_PATHLEN` (default 3). Issuance-time
budget check: `remaining = min over ancestors_i of (pathlen_i − distance_i)`; refuse with an
actionable `CaError` at 0; issued `pathlen < remaining` always (default `remaining − 1`).
Exceeding the budget cannot ship: refused at issuance and double-checked by the §5.2
self-verify, which exercises real OpenSSL path validation. The anchor's escape hatch is
same-key re-signature with a larger pathlen (nothing chained is invalidated).

---

## 7. Names and constraints: identity that can actually be contained

### 7.1 What was measured (S3, S4, F2b)

1. **Vacuous satisfaction**: a SAN-less leaf passes a critical permitted-URI constraint;
   constraints restrict only names that are present.
2. **CN checking is real for DNS constraints**: a hostname-shaped CN is checked against DNS
   subtrees (SAN-less `CN=evil.other.com` refused under `permitted;DNS:site1.example`;
   `CN=fed:uuid` passes — not hostname-shaped).
3. **Authorization never looks at SANs**: `node_api/base_controller.rb:53`,
   `worker_api/base_controller.rb:47`, `federation_api/base_controller.rb:47` all resolve
   callers from the CN.
4. **Id-only SAN authorization is insufficient** (F2b): a subordinate constrained to
   `<its-ns>` can mint `powernode://<tree>/<its-ns>/worker/<victim-id>` — in-subtree, so the
   constraint passes; resolving by `<class>/<id>` alone then authorizes the victim.

### 7.2 The rules that make containment real — and their sequencing (F1)

**Rule 1 — the CA constructs the URI SAN; callers never supply it.** Every newly issued leaf
carries exactly one `powernode://<namespace>/<class>/<id>` URI SAN built from authoritative
inputs, and the issuing flow **records the full URI on the subject's row** (`identity_uri` on
`NodeInstance`/`Worker`, and a parallel recorded-URI attribute on the federation peer).
**The `inbound_subject` transition, specified** (F-4): the federation route resolves the
calling peer by matching the forwarded Info-header CN against `inbound_subject` *before*
verification (`federation_api/base_controller.rb:31,46-47`), and Traefik forwards
`subject.commonName` only — and a full URI can exceed X.509's 64-char CN bound anyway. So the
certificate CN **stays `fed:<peer.id>`** and `inbound_subject` **keeps storing it as the
resolution key, unchanged**; the recorded full URI is a separate attribute checked at rule-3
time, after verification. Nothing about pre-verification resolution moves. Ships at increment
5, applies to all new issuance, zero fleet impact.

**Rule 2 — verifiers require the URI SAN on *delegated* leaves.** Discriminator, defined
(F1's missing definition): a **delegated leaf** is one whose verified chain — the
`StoreContext`-built chain the verifier already holds — contains at least one non-self-signed
CA between leaf and anchor (chain length ≥ 3). By §1.4 every live leaf is depth-1 (only
self-signed roots exist), so at increment 5 this rule matches **zero existing certificates**:
no de-authentication, no re-enrollment deadlock — `NodeEnrollmentService.refresh!` keeps
authenticating on the CN arm below until the node's own re-issue hands it a SAN. A
subordinate cannot evade it: everything a subordinate mints is depth ≥ 3 by construction.
After the §11 cutover, the final increment flips the rule to **all** leaves.

**Rule 3 — authorization is full-URI equality against the recorded identity, with a
quarantined CN arm.** When a verified leaf carries the URI SAN, the controller compares the
**entire URI** — namespace included — against the subject row's recorded `identity_uri`;
mismatch refuses, and there is no fallback from a present-but-mismatched SAN. This closes
F2b: the forged `…/<its-ns>/worker/<victim-id>` fails because the victim's recorded URI
carries the *victim's* namespace. When no SAN is present, the CN arm applies — permitted
**only** for non-delegated chains (rule 2 already rejected SAN-less delegated leaves), which
confines it to legacy and anchor-direct leaves that only the anchor hub itself can mint. The
CN arm is quarantined exactly like the legacy store read and **deleted in the final
increment** after cutover.

**Recording semantics for `identity_uri`** (F-5 — a new column; no occurrence exists in the
tree today):

- **Uniqueness**: unique index — one identity URI names one subject.
- **Absent record**: a verified SAN-bearing leaf whose URI matches **no recorded identity is
  refused** — stated, not implied. There is no resolve-by-parsing fallback.
- **Atomicity — record before deliver**: issuance writes `identity_uri` and the §9.1 registry
  row **in one transaction, before the cert leaves the hub**. The failure modes then order
  safely: a crash after recording but before delivery leaves a recorded URI with no cert in
  the field (harmless — the retry re-issues and re-records in-transaction); the reverse
  order would leave a node holding a SAN cert that refuses everywhere **and cannot
  authenticate to refresh** — the F-5c deadlock this rule exists to prevent.
- **Symmetric-peer scope**: rules 2/3 (and the delegated-leaf discriminator) apply to chains
  verified against **our own tree** — the two §4.4 scopes. A symmetric peer's leaves verify
  on the per-peer binding path against *its* recorded anchor and bind to the **peer row**,
  exactly as today; if that peer adopts hierarchy internally, its internal chain shape is its
  own business and triggers no local URI requirement. (The alternative — demanding recorded
  URIs for foreign subjects we never issued — would refuse every such peer; rejected.)

Namespace declaration is unchanged: `POWERNODE_CA_IDENTITY_NAMESPACE` at anchor generation;
per-subordinate sub-namespaces at approval. SPIFFE-compatible shape, conformance not claimed
(§19 Q2).

### 7.3 Constraints default ON

Critical `nameConstraints` (permitted URI subtree = the subordinate's namespace) by default;
per-subordinate opt-out at approval. With §7.2's three rules, containment is real: name AND
authorization are both bounded to the subtree's namespace.

### 7.4 The DNS dimension (S4)

OpenSSL checks hostname-shaped CNs against DNS constraints, so an enabled DNS scope refuses
every hostname-shaped CN outside it. Handled by the §5.2 probe matrix (fails at issuance, on
the parent) and by identity CNs remaining non-hostname-shaped by construction.

### 7.5 Serving SANs: the per-type either-or, all types (F11)

Leaves carry `serverAuth`, and any SAN type a subordinate may issue unconstrained is an
impersonation surface — DNS *and* IP (A2A/serverAuth here frequently rides overlay IPs). At
approval, the subordinate declares its serving scope **per name type**: a DNS subtree, IP
ranges, or neither; each declared scope is stamped as the corresponding permitted subtree,
and each **undeclared type carries no issuance right** — the subordinate's leaf path refuses
`sans:` entries of that type. One standing carve-out: **loopback** (`localhost`,
`127.0.0.1/8`, `::1`) is issuable by every subordinate regardless — it is unspoofable
cross-host, and without it a no-scope subordinate could not mint its nodes' localhost serving
certs (the F11 regression). The URI type is always the identity namespace and is never
optional. §13 carries the impersonation rows.

---

## 8. Trust distribution

### 8.1 Anchors-only at the handshake — made true by the writers

Handshake bundles (`caFiles`) carry trust anchors only: after block-split + fingerprint
dedup, an **anchor filter** admits only self-signed certificates; unclassifiable
(unparseable) blocks are dropped **loudly** (warn + drift signal — the §12 unification).
This is a proxy-layer statement: backends re-bind per §4.4's scopes on the PEM path, and the
one branch that *did* rest a backend decision on the handshake — the no-PEM forwarded-CN
fallback (F-1) — is structurally gated in §4.4 and deleted at the final increment, so once
trust material is tree-shaped no backend authorization decision rests on the handshake
widening. Leaf presenters send full chains; the proxy builds through them (assumption 2).

### 8.2 Chain presentation is a deliverable

Go agent, worker (`WorkerCertManager`), `Federation::PeerClient`, and Traefik-served certs
all move to fullchain presentation — per-holder work items with per-holder oracles; the
Rails-side *acceptance* oracle lives in increment 2 so neither side's test can go green for
the other. A holder that cannot present its chain cannot be enrolled deeper than depth 1.

### 8.3 Pull, generalized — on channels that exist (§16)

The trust-bundle pull exists and is scheduled (worker job → `TrustBundleRefreshService`).
Rev 4 generalizes it: source sets by explicit relationship predicates (parent via
`parent_peer`; symmetric peers via `peer_kind: "platform"` + spawn fields — never
`trusted_ca_pem` presence, which under §11.3 excludes the parent by construction), and the
pull becomes the CRL **exchange** of §9.3. Operators publish: anchor cert + CRLs. Never: keys.

---

## 9. Revocation — P0

### 9.1 The issued-cert registry (prerequisite — now lands with revocation, §15)

`System::CaIssuedCertificate`: `serial` (unique), `subject`, `fingerprint`, `is_ca`,
`not_after`, `revoked_at`, `revocation_reason`, `approval_request_id`. Written on every
issuance by both adapters; CRL source of truth; audit-gap closure.

### 9.2 Mechanism: CRLs (OCSP and bespoke lists rejected — unchanged rationale)

One X.509 v2 CRL per CA, signed by that CA (`cRLSign` universal); local: generated from the
registry to `<dir>/crl.pem`, present from birth (empty is valid), regenerated on revoke and
on a timer; Vault: native CRL mirrored to the same path. `nextUpdate = cadence ×
safety_factor` — **both settings, and the safety factor is a security knob, not just an
availability one** (F4): see the bound in §9.3. Recommended default `safety_factor = 2`.

**Legacy stores** (F7): the revocation increment's boot task emits an empty `crl.pem` into
legacy-shaped dirs too — explicitly acknowledged as the **one write this design ever makes
into a legacy layout**: additive, a new file, touching neither key nor cert, and required so
the universal fail-closed posture below does not fail the live fleet on its own root.

### 9.3 Distribution: the exchange, ingest rules, and the true relay bound (F3, F4)

**Transport — a channel that exists**: rev 3's heartbeat ascent is withdrawn (the outbound
heartbeat channel does not exist — §1.2). Both directions now ride the **existing, scheduled
trust-bundle pull**, upgraded to an exchange: the child-initiated request
`POST federation_api/trust_bundle/exchange` carries the child's CRL set (and the CA certs
needed to verify them) up, and the response carries the parent's full tree set down. One
verb on the existing controller, one change at the existing call site
(`TrustBundleRefreshService`), scheduled by the existing worker job — no new subsystem, no
new scheduler. **The cadence, printed** (F-3): the job runs **hourly** —
`worker/config/sidekiq.yml:702-706`, `federation_trust_bundle_refresh: cron: '40 * * * *'`.
(The `federation_heartbeat: every: '60s'` entry directly above it in the same file is a
*different* job — the inbound-staleness sweep — and is where any "60s-class" impression comes
from; do not re-derive the cadence from it.) Tree-wide convergence is therefore
**depth × cadence per direction** — each hop to the common ancestor and back down is an
independent hourly tick — not one cadence.

**Ingest rules — mandatory at every hop, both directions** (F4):

1. **Signature + membership**: a received CRL is stored or re-served only if it verifies
   against a CA certificate that itself **chain-verifies to the tree anchor** (tree
   membership is cryptographically checkable — no registry propagation needed; symmetric
   peers' CRLs verify against their recorded anchors instead). A garbage blob keyed to a
   cousin's fingerprint fails the signature and is dropped-and-alarmed — the cross-branch
   fail-closed DoS is structurally closed, because an attacker cannot produce a CRL that
   verifies against the victim CA's key. **That chain-verification of the issuer applies
   CRLs itself** (F-9): a CA whose own certificate is revoked has its CRLs refused at
   ingest — otherwise a revoked-but-key-holding subordinate's freshly signed CRLs would keep
   being ingested and re-served tree-wide. Cache pollution only (chain-time enforcement
   kills the branch regardless), but the ingest path says so explicitly rather than
   depending on it.
2. **Monotonicity**: never replace a cached CRL with one whose `crlNumber` (fallback:
   `thisUpdate`) is not strictly greater. A relay replaying genuinely signed older CRLs
   refreshes nothing and resets no staleness clock.
3. **Bounds**: one CRL per CA fingerprint; per-CRL byte cap and per-exchange count cap
   (settings); unknown/unverifiable issuers refused. The re-served set is the set of
   chain-valid tree CAs — bounded by the tree itself, not by what children claim.

**The relay bound, restated** (F4): a compromised or revoked relay cannot forge fresh
ancestor-signed CRLs; it can only withhold, or replay no-newer material (rule 2). Its
maximum self-extension is the remaining validity of the freshest pre-revocation CRL it
holds, plus grace: **`(safety_factor × cadence) + grace`** — not rev 3's `cadence + grace`.
The safety factor therefore trades availability tolerance directly against containment
latency; both knobs are settings, and the default recommendation (2× cadence, grace 3×
cadence) is stated in §19 Q3 for operator review. **In real numbers, with the hourly cadence
and those defaults** (F-3): `nextUpdate` = 2 h, relay bound = **5 hours** — the honest figure
behind every "leaves die within the bound" phrase in §13; anyone needing tighter containment
tunes the cadence, not the prose. One constraint is a **rule, not a tuning note**:
**`grace > (depth − 1) × cadence`**, or honest multi-hop propagation alone trips the
fail-closed posture — a CRL arriving at the tree's far edge is already `(depth − 1)` cadences
old. §17 adds the corresponding preflight check.

**Failure posture** — bounded staleness then fail-closed, universally: cached CRL honored
through `nextUpdate + grace`, then fail-closed for that CA; no cached CRL at all fails
closed (every CA publishes from birth; legacy stores receive theirs per §9.2/F7). The grace
window is **app-owned cache-loading logic** (OpenSSL hard-fails at `nextUpdate`): the cache
decides whether a stale-but-in-grace CRL is loaded (with alarm) or withheld (fail closed) —
owned and tested by the revocation increment.

### 9.4 Enforcement points and the walkthrough

App layer authoritative: `MtlsClientVerifier` checks CRLs over every verified chain element
in both §4.4 scopes, fed by the core checker reading the on-disk convention
(`revocation_provider` seam, §14). Walkthrough: revoke on the parent → registry +
`NodeCertificate` marked, CRL regenerated → exchange propagates (up and down) → app-layer
rejection tree-wide within the §9.3 bound. Proxy handshake acceptance confers nothing. Leaf
revocation: issuing-hub DB check (immediate) + issuer CRL for cross-hub verifiers.

---

## 10. Rotation

**Anchor rotation**: generate new anchor (§3.1 parameters); distribute both anchors during
overlap (the two-root bundle the per-root retry exists for — §12); re-sign each direct
subordinate's existing key under the new anchor; leaves migrate at renewal cadence; retire
the old anchor from distribution when the registry says nothing chains to it. Never revoked —
just no longer distributed.

**Intermediate rotation**: renewal (same key) — auto-approvable, zero leaf impact; same-DN
same-key cert pairs legitimately coexist during overlap (fingerprint dedup + the §4.4
same-DN retries are what make that safe). Re-key — full ceremony, RE-ENROLLING staging,
leaves migrate on their own cadence; re-key **for compromise** = revoke the old cert and let
its leaves die: containment working.

---

## 11. Bootstrap and cutover: from an existing flat root to the clean hierarchy

A runbook, not an architecture. Re-mint and re-enroll, once, operator-scheduled; the
campaign's code lands before the cutover and keeps legacy stores working; the deletion commit
lands after it, gated (a dev-loop gated decision).

### 11.1 Fresh install

Nothing to do: first issuance mints a §3-layout anchor. An intended-subordinate-from-birth
starts the ceremony before first issuance; the `pending/` marker (plus its DB row) keeps
lazy generation from preempting it.

### 11.2 Cutover of a deployment with a live pre-hierarchy root

1. **Stand up the tree top-down.** New anchor on the chosen root. Before the old CA dir is
   moved aside, **mint the retired anchor's terminal CRL** (F-2): while the old key is still
   live, sign one final CRL — carrying any revoked serials, empty otherwise — with
   `nextUpdate` = the planned window deadline plus margin. Without it, the F8 window
   collides with §9.3's own posture: an old-root leaf's chain is `[leaf, old-root]`, §9.4
   checks every element, and the old root's CRL would otherwise sit unrefreshable in the
   moved-aside directory (re-signing needs the set-aside key), failing the whole window
   closed. The terminal CRL travels with `retired-anchors.crt`; no verifier exemption
   exists — and its expiry **is** the window's hard, fail-closed end (the bound enforcing
   itself). Then move the old dir aside (old key destroyed at step 5, not before) and enroll
   subordinate hubs via §5, staged, no blackouts.
2. **Re-enroll every leaf** via the existing CSR-only refresh path; new leaves carry URI
   SANs and full chains. **The old-root leaves must keep authenticating while this runs**
   (F8): re-minting replaced `own_ca_pem`, and §10.1's overlap covers handshake bundles
   only — `chain.crt` cannot carry a retired anchor (it is not an ancestor). The runbook
   therefore writes the old root into **`retired-anchors.crt`** (§3 layout), an explicit
   additional trust input that `verify_request`'s own-subject scope unions in for the
   window's duration. It is a cutover artifact with a lifetime, not general trust config.
3. **Swap trust** — bundles carry the new anchor (+ the retired anchor, window only). This
   is also the moment every hub's trust material becomes tree-shaped, so the §4.4 F-1 gate
   engages fleet-wide: the no-PEM CN fallback stops being reachable, and the runbook's
   preflight confirms PEM forwarding is active on every route before this step (the
   writers' coupling makes it so; the check makes it visible).
4. **Verify** — same `anchor_fingerprint` everywhere, expected chain lengths, CRL freshness;
   drift sensor flags any remaining old-root presenter. Exit criterion for step 5.
5. **Retire.** `retired-anchors.crt` deleted everywhere; old key destroyed; anything not
   re-enrolled stops authenticating — the cutover completing. Then the gated final commit:
   legacy store read deleted, `root.crt` source deleted, §7.2's rule 2 flipped to all
   depths, the CN authorization arm deleted, **the no-PEM fallback branch deleted** (its
   structural gate has made it unreachable since step 3), and the dead-reference sweep
   (incl. `extensions/system/docs/runbooks/federation-troubleshooting.md:226`).

### 11.3 What replaces the flat-child convention — and that it is deleted

`federation_peer.rb:152-154` is deleted with its convention. Readers: `trusted_ca_pems`
(`:159`), `TrustBundleRefreshService` (`:56` — re-keyed per §8.3), and — load-bearing —
`federation_api/base_controller.rb:57`, which routes tree members (nil anchor) to the
**cousin-capable scope** of §4.4 (`anchors: [anchor_cert]` + presented chain): exactly what
makes a cousin's inbound call verify. Replacement semantics: `trusted_ca_pem` populated
**iff** symmetric peer (anchor outside our tree; full chain stored), predicate explicit
(`peer_kind: "platform"` + `spawn_mode`/`spawn_role` — real columns), validation enforcing
the iff both ways. No data migration (zero rows, §1.4).

---

## 12. Deleted as legacy vs retained-and-re-justified

**Deleted (sequencing noted):**

| Item | Where | Replaced by |
|---|---|---|
| `root.key`/`root.crt` names + legacy read | `LocalCaAdapter` | §3 layout; read deleted in the final increment, post-cutover |
| `root.crt` ingress source | `ingress_config_writer.rb:644` | `chain.crt`; same commit |
| `root_cert` | `:130` | `issuing_cert`/`anchor_cert`; zero callers incl. specs |
| Local `revoke` no-op | `:366` | Registry-backed CRLs (§9) |
| In-memory best-effort persistence | `:286-293` | Issuance refuses on an unpersisted CA; §17 preconditions |
| Flat-child `trusted_ca_pem`-nil convention + comment | `federation_peer.rb:152-159` | §11.3 iff semantics + validation |
| Unconstrained / serial-1 / pathlen-less / DB-parameterized anchor generation | `:372` | §3.1 env-parameterized; existing anchors re-minted (§11) |
| `CloudSeed` rescue-to-fixture | `cloud_seed.rb:143-156` | Fail loudly (defect fix, increment 1) |
| CN-based mTLS authorization | the three base controllers (§7.1.3) | §7.2 rule 3 — the CN arm quarantined to non-delegated chains, deleted in the final increment |
| No-PEM forwarded-CN fallback | `mtls_trust.rb:80-83` | §4.4's structural gate (refuses once trust material is tree-shaped — F-1); branch deleted in the final increment, its comment being the textbook case for the §16.1 premise sweep |
| Prior revs' own bridges (cross-sign migration, dual-anchor grandfathering, CRL carve-out, day-one legacy refusal, heartbeat-borne ascent) | (this document) | §11 cutover; §9.3 universal posture + exchange |

**Retained — re-justified (update the comments; keep the code):**

| Mechanism | Comment says | Real ground here |
|---|---|---|
| SHA-256(DER) dedup, never DN | Legacy same-DN hubs | Rotation overlap and same-key renewal put same-DN (even same-key) cert pairs in one bundle — only fingerprints distinguish trust material |
| `MtlsClientVerifier` per-root anchor retry (`:87-99`) | Same-DN legacy collision | Load-bearing for §10.1 overlap bundles; §4.4 adds the presented-chain analogue for the same reason |
| `CaFingerprint` over subject DN | Legacy collision | Correct on its merits; the tree identity stands on it |
| Never-rewrite live CA; fail-closed half-pair; **now also key↔cert match at load** | Protect legacy roots | Operational safety in any era; the staged `pending/` key is the deliberate exception (destroyable — nothing issued off it) |
| Unparseable-anchor handling (extension keeps by intent `:128-129`; core drops `:661-663` — opposite postures) | — | Unified by the §8.1 anchor filter: unclassifiable blocks are excluded from handshake bundles **loudly** (warn + drift), never silently destroyed |

---

## 13. Threat model

| Compromise | Blast radius | Detection | Containment |
|---|---|---|---|
| **Leaf key** | That identity | Audit anomalies; sensors | Issuer-DB revoke (immediate) + issuer CRL (within the §9.3 bound); 90-day TTL |
| **Issuing authority** | Identities within its URI namespace (§7.2 full-URI rule); serving impersonation only within its declared per-type scopes (§7.5 — undeclared types unissuable; loopback carve-out is cross-host-unspoofable) | Parent-side reconcile of issued-cert vs enrolled-instance counts; canary identities | Parent revokes the serial; leaves die within the bound |
| **Intermediate** | Above + minting CAs within pathlen and namespace | As above; a subordinate without a matching parent-side approval row = high-severity drift | Parent revokes; branch dies together. **Self-preservation bound**: withhold/replay only — max extension `(safety_factor × cadence) + grace` = **5 hours at the real hourly cadence with proposed defaults** (§9.3), plus depth × cadence propagation; "dies within the bound" means hours-scale, not minutes |
| **Anchor key** | The tree; revocation unenforceable | External: peers pinning our anchor fingerprint; unapproved-issuance review | None in-tree — emergency re-root (§10.1). Anchors sign rarely, delegate everything |

**Not protected against**: online anchor key (no HSM/offline ceremony — §18); a malicious
parent (inherent; cross-org = federation, never subordination) — stated at F-7's measured
precision: an intermediate ancestor's forged leaves chain-verify on a descendant's
own-subject routes but are **delegated** (chain ≥ 3), so §7.2's rules refuse them for want of
a recorded URI; the **anchor's own** chain-length-2 leaves are non-delegated, ride the CN arm
with **no URI check at all until the final increment**, and are bounded only by "only the
anchor can mint chain-length-2" — which is this row restated, nothing stronger; the proxy-handshake revocation
window (bounded); host compromise of a CA hub ≈ that CA's compromise; pre-cutover exposure
(the fleet runs the old flat posture until §11 completes); volatile CA storage defeating
§3.1's guarantees (a §17 precondition — detection exists, prevention is deployment).

---

## 14. Core / extension boundary

Unchanged in shape: core verifies (`MtlsTrust` two-scope verification, `MtlsClientVerifier`
path-building + SAN rules + CRL checking, `CaFingerprint`); extension issues
(`InternalCaService`, adapters, state machine, ceremony, approval source, registry, CRL
generation, exchange endpoint, bundle writers/refresh). Seams: the path convention
(`POWERNODE_CA_LOCAL_DIR` with `live`/`versions`/`crl.pem`/`retired-anchors.crt`/`pending/`),
the `own_ca_provider` + new `revocation_provider` injectables, and core's `ApprovalRequest`
consumed extension→core. Core mode: nothing issuance-side activates. Vault-less: everything
on the local adapter.

---

## 15. Increment plan

Ordering rules: verifier before anything cross-branch (S1); **revocation before the
subordinate verb** (F9 — nothing mintable before revocable, now literally: the verb lands
after the CRL machinery and demands an `approval_request_id`); identity binding before the
ceremony (S3); every fleet-visible flip sequenced per §15.1. Offline test strategy as before;
WebMock never stubs the behavior under test.

1. **Chain-aware representation, additively.** §3 v2 layout (version-dir + symlink; legacy
   read retained), chain contract, `root_cert` deleted, fingerprint split,
   +`chain.crt` source, cross-reference comments, §12 re-justifications;
   **`parse_issuer` re-derived** (`node_enrollment_service.rb:170-176` — the second depth-1
   parse, §4.2): `issuer_subject` becomes the leaf cert's own `.issuer` DN, chain never
   parsed, column comment restated (diagnostic; fingerprint is identity); defect fixes:
   `CloudSeed` loud failure, in-memory fallback removal, key↔cert load assertion.
   *Oracles*: in-process chain fixtures; anchor-terminal fingerprint; legacy-shaped dir
   loads byte-identically (the S2 guard); mismatched key/cert pair refuses;
   **`issuer_subject` records the intermediate's subject (not the anchor's) for a
   chain-issued cert, and the unchanged root subject at depth 1** — the pair that fails
   against both the old first-cert parse and any chain-order mistake.
2. **Core verifier: two scopes + path building (§4.4) + anchor filter (§8.1) + the F-1
   no-PEM gate** (inert on flat deployments; engages on tree-shaped trust material).
   *Oracles*: the S1 killer on the federation scope; the **same leaf refused on a node
   route** (the F2 guard); no-presented-chain negative; F10 same-DN mutant chain; parse-cap
   overflow; bare-leaf depth-1 byte-identical — including the no-PEM CN fallback on a flat
   store; the **same no-PEM request refused once the trust input is tree-shaped** (the F-1
   guard); two-anchor overlap bundle still passes. §15.1 note: the parser flip narrows one
   input shape (F-8) — a client sending trailing junk after the first comma-joined element
   goes from silently-accepted-by-truncation to refused; none known today, and the refusal
   is the correct behavior, but the row says so.
3. **Revocation + registry.** Registry model; CRL generate/sign; real local `revoke`;
   empty-CRL-at-birth **and the F7 boot task writing empty CRLs into legacy stores** (the
   one legacy write, acknowledged); the §9.3 exchange verb + refresh-service payload + fixed
   scope predicates; app-owned grace cache; core CRL check + `revocation_provider`.
   *Oracles*: revoke-intermediate → fail; fresh pass / in-grace pass-with-alarm /
   beyond-grace fail / no-CRL fail; **ingest**: unverifiable CRL dropped-and-alarmed (victim
   subtree unaffected), non-monotonic replay rejected, caps enforced; two-hop WebMock'd
   exchange converges a cross-branch CRL; withheld-CRL expiry at the **restated** bound.
4. **Subordinate issuance verb + budget.** §5.2 stamping + probe-matrix self-verify; §6
   budget; `subordinate_csr` (staged, locked); `approval_request_id` required at the adapter;
   `VaultPkiClient` verbs (labeled offline-UNPROVEN). *Oracles*: budget refusal; self-verify
   mutation oracle; missing-approval-reference refusal; CSR-smuggling regression pin.
5. **Identity binding + constraints (§7).** Rule 1 (URI SANs + recorded `identity_uri`),
   rule 2 (delegated-leaf discriminator), rule 3 (full-URI equality + quarantined CN arm),
   default-on constraints, §7.5 per-type scopes + loopback carve-out.
   *Oracles*: SAN-less **delegated** leaf rejected; SAN-less **depth-1** leaf still
   authenticates end-to-end (the F1 guard — a legacy-population fixture, mandatory);
   full-URI mismatch (right id, wrong namespace) refused (the F2b guard); out-of-namespace
   URI fails at OpenSSL; hostname-CN probes; undeclared-type SAN refused at issuance;
   loopback SAN issuable by a no-scope subordinate.
6. **CA-store state machine + ceremony.** §3.1 in full (lock, staging, key-match, atomic
   flip + dir-fsync, abort-as-parent-revoke, collection deadline, DB-row loss detection);
   ceremony endpoints + three gates + the §5.3 approval work; §11.3 semantics + validation;
   reconcile drift signal. *Oracles*: state matrix incl. crash-recovery at every flip stage
   and the concurrent-stager race; approval-less request leaves **no registry row**; abort
   after approval revokes parent-side; expired-collection auto-revoke; parent gates as real
   in-process request specs; full two-hub ceremony ending in a child-issued leaf verifying
   to the parent's anchor — and **refused on the parent's node route** (both §4.4 scopes in
   one flow).
7. **Chain presentation by holders** (Go agent, worker, `PeerClient`, Traefik files) —
   per-holder oracles; Rails acceptance already proven in increment 2. Holder rollout gated
   on the assumption-2 live smoke (§15.1).
8. **Cutover tooling + runbook + the gated final commit.** §11.2 automation incl.
   `retired-anchors.crt` **and its terminal CRL** (F-2); then, post-cutover: legacy read
   deleted, `root.crt` source deleted, rule 2 universal, CN arm deleted, **no-PEM branch
   deleted**, dead-reference sweep. *Oracles*: fixture legacy fleet through the cutover;
   old-root leaves authenticate **during** the window **with CRL checking fully enforced**
   (the F-2 guard — this fails without the terminal CRL) and a holdout fails **after**; an
   expired terminal CRL fail-closes the window (the self-enforcing deadline); post-deletion
   legacy dir refuses.

### 15.1 Per-increment live-fleet impact (standing section)

For each increment: what changes on a deployment running today's cert population
(SAN-less, depth-1, legacy store layout) the moment it deploys — and whether the
verification gate can see a regression there.

| Inc | Live-fleet impact on deploy | Gate visibility |
|---|---|---|
| 1 | Additive, legacy read retained — with two failure-mode changes stated (F-8): `CloudSeed` goes from silently-wrong trust material to a loud provisioning error, and **the in-memory persistence fallback's removal means a deployment limping on an unwritable CA dir loses issuance loudly** instead of minting per-process ephemeral certs. Both intended; both visible | Legacy-fixture boot spec (mandatory, listed); unwritable-dir refusal spec |
| 2 | Bare-leaf depth-1 verification byte-identical; today's bundles contain only self-signed roots, so the anchor filter emits identical bytes; the F-1 gate is inert on flat stores. One narrowing (F-8): the take-first parser becomes parse-all + refuse-overflow, so trailing junk after the first comma-joined element flips from accepted to refused — none known today | Byte-identical + F-1-gate + junk-tail oracles listed |
| 3 | Fail-closed CRL posture activates — **safe only because the same increment's boot task writes empty CRLs into every store, legacy included** (F7). Deploy order within the increment: CRL emission before enforcement | Spec: legacy fixture store gains a CRL at boot and its leaves still verify |
| 4 | None: verb has no callers; adapter refuses without approval reference | Refusal spec |
| 5 | **Zero by construction** (F1): rule 2 matches no depth-1 leaf; rule 3's CN arm serves the entire live population; new issuance starts carrying SANs + recorded URIs | The mandatory legacy-population fixture spec |
| 6 | None until an operator runs a ceremony | Ceremony specs |
| 7 | Holders start presenting chains — contingent on the assumption-2 Traefik smoke; **rolled out per-holder after that smoke, not before** | Go/holder tests prove presentation; smoke is the acceptance gate (named residual) |
| 8 | The cutover itself (operator-scheduled maintenance); the deletion commit only after it | Bidirectional cutover fixtures; gated decision |

---

## 16. Mechanism inventory — does the channel exist? (standing section)

Every mechanism this design leans on, with its existence and call site. A future revision
adding a dependency adds a row *first*.

| Mechanism | Exists? | Called from (today) | Design's use |
|---|---|---|---|
| Trust-bundle pull | **Yes, scheduled HOURLY** (`worker/config/sidekiq.yml:702-706`, cron `'40 * * * *'` — the `every: '60s'` entry above it is the unrelated inbound heartbeat sweep) | `worker/app/jobs/federation_trust_bundle_refresh_job.rb` → `worker_api/federation_trust_bundle_controller` → `TrustBundleRefreshService` → `PeerClient#fetch_trust_bundle` | Becomes the CRL exchange (§9.3); scope predicates fixed (§8.3); this cadence is the number in every §9.3 bound |
| Trust-bundle serve | Yes | `federation_api/trust_bundle_controller.rb` (mTLS) | Gains the exchange verb |
| Outbound peer heartbeat | **No** — `HeartbeatController` has zero callers; `PeerClient` has no heartbeat method; sweep is inbound-staleness only | — | **Not relied on** (rev 3's ascent withdrawn, F3) |
| Leaf enrollment/refresh (CSR-only) | Yes | `NodeEnrollmentService.enroll!/refresh!`, node agent | Cutover re-enrollment (§11.2) |
| Spawn acceptance token | Yes (7-day TTL) | `SpawnPlatformService` | Ceremony gate 1 (§5.3) |
| Core approval machinery | Yes (core sources only) | `Ai::ApprovalRequest` + `on_approval_decision` implementors | Gate 3 — **extension source is NEW work**, specified (§5.3) |
| `own_ca_provider` boot wiring | Yes | `powernode_system/engine.rb:162` | Unchanged; the reason for §11/§15 sequencing |
| `revocation_provider` | **New** (mirrors `own_ca_provider`) | — | §9.4, increment 3 |
| CRL exchange verb + payload | **New** (one verb on the existing controller + one call-site change) | — | §9.3, increment 3 |
| Presented-chain verification | **New** (measured absent) | — | §4.4, increment 2 |
| Worker-dispatch of periodic jobs | Yes | worker → server HTTP API (architecture rule) | Exchange cadence rides it |

### 16.1 The backward check — changed-premise sweep (standing section)

The other two standing checks look forward ("does this channel exist", "what breaks when this
lands"). F-1 needed a **backward** one, and it generalizes: **when a design changes a global
property, search the code for prose that documents a premise about that property** — comments
state premises in plain English, and the no-PEM branch's "our-CA-only" comment would have
surfaced in seconds under a search for the property this design changes. Procedure, per
revision: for each global property changed (this design's: what the handshake bundle
contains; what `ca_chain_pem` returns; what a CN means; what `trusted_ca_pem`-nil means;
where revocation is enforced), grep comments and docs for assertions of the *old* property
and disposition every hit — updated, quarantined, or deleted, in §12. Applied retroactively
here, the sweep's known hits are: `mtls_trust.rb:80-83` ("our-CA-only" — F-1, gated),
`traefik_config_writer.rb:113-115` ("verifies against our CA only" — preserved by the
two-scope split, comment updated to say precisely how), `federation_peer.rb:152-154`
(flat-child nil — deleted), `spawn_platform_service.rb:38-39` ("minutes-to-hours" — false
today, fixed in passing), `internal_ca_service.rb` adapter comments (updated by increment 1),
and `federation-troubleshooting.md:226` (rewritten at increment 8).

---

## 17. Environment and durability preconditions (standing section)

What the CA store requires of its host, stated as checked preconditions.

1. **Durable storage** (F6). `POWERNODE_CA_LOCAL_DIR` — including `pending/` — must survive
   reboot. The shipped default (`/var/lib/powernode/internal-ca`) is **not durable on
   overlay-rooted nodes**, where `/` is a volatile RW overlay and only the persistent tree
   survives (verified on this project's fleet); deployment profiles for such nodes MUST
   point the variable at the persistent tree. Checks: (a) every rename is followed by a
   parent-directory fsync (§3.1) — durability of the flip itself; (b) the ceremony's DB row
   detects staged-material loss after a reboot and keeps generation suppressed once the DB
   is up (§3.1) — detection, with the pre-DB residual stated there; (c) preflight reports
   the store path and whether a prior loss was detected. Prevention is the deployment's
   declaration; this section makes it a named, checkable requirement instead of an
   assumption.
2. **Single writer**: all mutating store operations under `flock(<dir>/.lock)`; the store
   must live on a filesystem with working POSIX `flock`, atomic `rename(2)`, and symlinks —
   which excludes network filesystems without those semantics.
3. **Permissions**: store dir 0700; keys 0600; the service user owns the tree.
4. **Clock sanity**: CRL validity (`thisUpdate`/`nextUpdate`) and certificate windows
   require roughly synchronized clocks across the tree; the preflight compares local time
   against the parent's bundle response time and alarms on skew beyond a setting.
   **Grace-vs-depth** (F-3): the preflight also checks `grace > (depth − 1) × cadence` —
   the §9.3 rule — using the hub's own chain length as the depth floor; a violation means
   honest propagation alone will trip fail-closed at the tree's far edge.
5. **Process environment at generation**: `POWERNODE_CA_PATHLEN` /
   `POWERNODE_CA_IDENTITY_NAMESPACE` must be present in every context that can trigger lazy
   generation (rake, proxy writer, boot) — i.e. set at the service-manager level, not only
   in the web process.

---

## 18. Out of scope, deliberately

HSM custody / offline-root ceremony (§13 residual; verb-shaped adapter surface leaves room);
OCSP (rejected, §9.2); proxy handshake-layer CRL enforcement (unavailable; CRLs feed it for
free if that changes); SPIFFE conformance (§19 Q2); the public-certificate plane (`Acme::*`);
deployment strategy for hubs; cross-organization trust (federation, never subordination).

## 19. Open questions

1. **Vault subordinate topology** — mount-per-hub vs mount-per-tier; leaning mount-per-hub;
   the Vault arm is offline-unprovable either way (§15).
2. **SPIFFE ID conformance** (`spiffe://` vs `powernode://`) — operator policy.
3. **CRL cadence / safety factor / grace defaults** — mechanism decided (§9.3); the values
   are operator policy with a stated coupling: the safety factor is both the availability
   window and the relay's containment bound. Proposal: cadence = refresh-job cadence
   (**hourly today** — §9.3), safety_factor 2, grace 3× cadence — which makes the relay
   bound **5 hours** and satisfies `grace > (depth − 1) × cadence` up to depth 4. Operators
   wanting tighter containment shorten the cron, not the grace.
4. **Anchor pathlen default** (`POWERNODE_CA_PATHLEN`, shipped 3) — recoverable post-GA via
   same-key re-sign.
5. **Assumption 2's Traefik half** — chain-presenting client vs anchors-only caFile at the
   handshake; first live-smoke item; also the gate for increment 7's rollout (§15.1).
6. **Cutover scheduling** — which deployment becomes the anchor; the maintenance window.
7. **Acceptance-token TTL for CA-capable spawns** — the shorter default is policy.
8. **Agent-level identities** as URI-SAN leaves under site authorities — follow-on.
