# Repo-less Modules

> Status: proposed (design note — not implemented)

> How the platform can create module content without a git repository: per-instance
> configuration as union layers, an authored-content store, and a third build lane.
> Records what already exists, the one true gap, and the decisions that are the
> operator's rather than the implementer's.

## Table of Contents

- [Requirement](#requirement)
- [What already exists](#what-already-exists)
- [The root gap: nothing can store authored content](#the-root-gap-nothing-can-store-authored-content)
- [Delivery is the union, not extraction](#delivery-is-the-union-not-extraction)
- [Proposed design](#proposed-design)
- [Attestation and trust](#attestation-and-trust)
- [Validation: stronger than the repo path](#validation-stronger-than-the-repo-path)
- [Lifecycle without a repo](#lifecycle-without-a-repo)
- [Open decisions for the operator](#open-decisions-for-the-operator)
- [Verified vs inferred](#verified-vs-inferred)

## Requirement

> "We need the ability to create modules without repos."

Today a platform module's content originates as `modules/<slug>/` in
`powernode-system`, is built from a git checkout, signed, and published. That
serves fleet-wide code well and serves *per-node and per-instance configuration*
badly: a config file that differs per instance has no business being a commit,
and an instance cannot author one without a repo write credential — a credential
whose blast radius is every node that builds from that repo.

This note records how to close that, and deliberately records what is **already
built** first, because three separate investigations of this question each
concluded "the mechanism is missing" and each was wrong in a different way.

## What already exists

**Module rows without repos already exist, in three flavours.**

| Flavour | How created | Content production |
|---|---|---|
| Operator-authored | `node_modules_controller` CRUD (all five spec fields) | none |
| Package-materialised | `PackageModuleMaterializer` (`auto_generated`, `PackageModuleLink`) | **yes** — the package lane |
| Dependant child | `NodeModuleAssignment.create_dependant!` | none |

**Two build lanes exist, and only one needs a repo.**

- `ci.module_build` — `module-forge-build.sh` clones `MODULE_SOURCE_URL@BUILD_SHA`
  and requires `modules/$MODULE/manifest.yaml` in that checkout. Repo-bound by
  construction.
- `ci.package_build` — `module-forge-package-build.sh` builds "straight from a
  package recipe that travels entirely in the environment, since there is no
  `modules/<slug>` tree / `manifest.yaml` to check out" (its own header). The
  recipe ships in task options (`NativeModuleBuildOrchestrator#package_task_options`);
  the builder-side handler is registered as `ci.package_build`
  (`agent/internal/runtime/tasks/handlers/package_build.go`). It reuses the same
  chroot skeleton, `push.sh`, and the same sign → `ingest_native!` tail.

**This refutes the intuition that repo-less builds need a new paradigm.** The
recipe-in-environment pattern is established and in production. What the
requirement needs is a *third lane*, not a new production model.

**A node-originated content channel is also already designed.**
`powernode-agent commit` captures the overlay upper-dir delta, rsync-filtered by
the manifest's file spec — which for a dependant *is* the parent's
`dependency_spec` — plus `mask`, `protected_spec`, and a hardcoded deny list
(`/etc/shadow`, `/etc/sudoers`, `/etc/ssh/ssh_host_*_key`, `/root/.ssh`, both PKI
paths, `/var/lib/cloud`). It secret-scans, stages locally for review, then POSTs
to `node_api/modules/:id/versions` under the node's **mTLS identity — no repo
credential**. Versions land `promotion_state: "built"` and require explicit
operator promotion.

So "let instances author their own instance modules, with spec adherence
enforced and an operator gate" is the platform's own intended answer. It is
unfinished, not absent.

## The root gap: nothing can store authored content

The single blocking defect, and it is small and specific:

- `NodeModule#set_data_file(filename:, content:)` stores `data_file_name`,
  `data_file_size`, and a SHA256 in `data_checksum` — and **drops the `content`
  argument**. It has zero callers.
- `AgentModuleCommitService` verifies the uploaded tar's sha256 and then
  persists only name/size/checksum. **The bytes are discarded.**
- Blob serving is OCI-registry proxy only (`FilesController` →
  `OciBlobProxyService`). There is no DB-bytes path.

Consequence: a committed or authored version records a checksum of content that
no longer exists, and can never become mountable. Every other piece — rows,
versions, diffing, promotion, audit, rollback — is built around content that the
platform cannot hold.

Two adjacent defects on the same path: the versions endpoint scopes to
`current_node.node_modules`, which is assignment-joined, and dependant children
have no assignment row — so the very modules the commit flow targets return 404.
And `create_dependant!` has no callers anywhere.

## Delivery is the union, not extraction

An earlier draft of this design proposed an agent-side applier that would fetch a
data file and write it to a `copy_path`. That was wrong. The intended shape is a
**higher-priority overlay layer**:

```ruby
# node_module_category.rb
# Default `position` offsets so subscription < config < instance in
# effective_priority. Each step is a full PRIORITY_CATEGORY_MULTIPLIER
# bump on NodeModule (ensures children sit above parents in the union).
DEFAULT_POSITION_OFFSETS = { "subscription" => 0, "config" => 1, "instance" => 2 }
```

Four mechanisms only cohere under that reading: the variety offsets put children
above parents; `file_spec` on a dependant delegates to `parent.dependency_spec`,
so a child cannot *name* an unreserved path; the parent's `dependency_spec` folds
into peers' `effective_mask` so the reservation is exclusive; and
`protected_spec` flows into every neighbour's mask so sensitive paths can never
be overridden. Delivery plumbing already treats dependants as ordinary union
members — the `node_api` module index includes dependant children without an
assignment row, and the agent mounts them through the normal attach path at
instance priority with no special-casing.

`manifest.CopyPath` is declared in the agent (`internal/manifest/types.go`) and
**never read**. It is superseded by union composition. The server still advertises
it — the summary serializer claims "agent writes this module's data file into
`destination_path` at attach time", which is false. Either delete the field
across agent struct, serializers, model and UI, or at minimum correct the
comments; leaving it is an attractive nuisance.

**Not every dependant needs a blob.** `DockerDaemonOverridesResolver` delivers
per-node and per-instance settings as structured JSON in the dependant's `config`
column, priority-merged and consumed by the agent's dockerd manager. The split is
deliberate: **files → blob layer; agent-interpreted settings → config JSON.**

## Proposed design

1. **Authored-content store.** Persist a content-addressed file map
   (`path → bytes`, mode, owner) per `NodeModuleVersion`. This is the root fix;
   nothing else works without it.
2. **A third build lane, `authored`**, cloned from the package lane: one forge
   script, one builder-agent handler, one orchestrator branch. It fetches the
   content by digest over mTLS (a small new `node_api` endpoint — do **not**
   inline bytes into task options; keep those small), runs `mkfs.erofs` with the
   determinism flags `stage2-carve.sh` already pins (`SOURCE_DATE_EPOCH`, `-T`,
   `-U`), computes the fs-verity root, and runs `push.sh`.
3. **Reuse the existing tail verbatim**: `ModuleSigningService.sign!` →
   `ingest_native!` (records the erofs *layer* digest and fs-verity root) →
   promotion. Lease, retry, push, sign, verify, ingest and publish are all
   unchanged.
4. **Zero new code on consuming fleet agents.** One new handler on the *builder's*
   agent. Consuming nodes mount an ordinary blob.
5. **Terminate the commit pipeline in the same rails** once the byte-discard and
   dependant-404 defects are fixed: committed tar becomes `authored`-lane input.

**Granularity: one blob per dependant** (per parent × node/instance). It matches
the DB identity, preserves parent-scoped reservation semantics, allows
independent attach/detach, and gives digest-diff drift detection. Aggregating all
of a node's config into one layer churns a single artifact on any change and
destroys the per-parent scoping.

**Self-hosted caveat.** ops-hub cannot lease builders (its egress blocks
Proxmox), and `erofs-utils` ships only in `module-forge` — the control plane has
`oras` and `cosign` but no `mkfs.erofs`. Either keep a persistent builder for the
control plane, or accept adding `erofs-utils` + `fsverity` to the hub stack as a
local fallback behind the same seam. Fleet-wide, use the builder route.

**Overlay limit.** The binding constraint is the `mount(2)` option page (~4096
bytes), not the kernel's layer cap: each layer contributes
`/run/powernode/modules/<64-hex>` ≈ 88 bytes to the single `lowerdir=` string,
giving a ceiling around 45 layers. Roughly 20 are in use today, so per-instance
layers are fine at realistic counts — but add a compose-time count/length
guardrail rather than discovering the limit at boot.

## Attestation and trust

**What signing should mean for a repo-less artifact:** *the control plane
rendered this artifact from persisted, versioned state S (digest D), authored by
principal P, at time T.* Platform provenance and state binding — **not** source
review. Concretely: a separate **materializer key**; an OCI annotation carrying
the authored-content digest and version id so the artifact→DB binding is
verifiable; author, content digest and `generated_at` recorded in the version's
`config` JSONB.

**Signing DB-derived content with the build key would not be a novel category
error — the premise is already diluted.** Package modules' content never lived in
the repo either (upstream debs, recipe in task options) and is signed with the
same identity. But distinguishable provenance is nearly free here, so it is worth
taking: build key = "the pipeline built this from declared inputs"; materializer
key = "the control plane rendered this from DB state".

**The enforcement gap to close.** Server-side key verification tries *every* key
in `trusted_public_keys`, so with a flat list a materializer-signed artifact
verifies for a repo-backed module and vice versa. Per-module pinning exists
(`cosign_identity_regexp`) but is honoured only on the webhook `ingest!` path,
**not** on the native path. Enforcement = apply per-module key pinning on **both**
ingest paths: repo-backed modules pinned to the build key, authored modules to
the materializer key. Existing columns; small change.

**Honest caveat that must travel with this design.** None of the above is
enforced on-node today. The live reconciler is wired with `verify.AlwaysOK{}`
(whose `VerifyBlob` returns nil unconditionally) and fs-verity is never passed,
so the runtime trust root is `sha256(blob) == digest served over mTLS`. The key
split buys ingest-time enforcement, audit clarity and future-proofing — not
runtime enforcement. When agent-side verification is eventually enabled, note
that `CosignVerifier` takes a single `KeyPath` and will need the same
try-multiple-keys extension the server already has. **This gap between the
agent's documented and actual integrity model should be tracked as its own item,
independent of this design.**

## Validation: stronger than the repo path

For authored modules the platform *is* the builder, so validation can be total
and server-side at version-create:

1. authored paths ⊆ declared `file_spec`;
2. for dependants, ⊆ `parent.dependency_spec` (automatic via the delegation);
3. reject any path matching the **union** of `protected_spec` across the
   account's modules — deliberately conservative, to dodge the target-scoping
   weakness below;
4. port `commit_cmd`'s hardcoded deny list server-side as a floor (the server has
   no equivalent today).

This is categorically stronger than the repo path, where adherence rests on a
builder's rsync filter plus reviewer attention.

**Two corrections to the "structural adherence" claim**, both of which narrow it:

- The `dependency_spec` → peer `effective_mask` reservation is **conditional** —
  it applies only when the parent is higher-priority **and** `lock_spec`. A
  non-locked parent reserves nothing.
- Adherence holds at **build/capture time only**. At mount time the agent mounts
  whatever blob the digest names, with no path filtering; runtime `protected_spec`
  enforcement is explicitly forward-compat and its only current use is hot-prune.
  A maliciously-built blob published under a dependant would mount and win the
  union.

**The hole for non-dependants.** An operator-authored *non-dependant* module has
no parent reservation and a free-form `file_spec`. What protects it at build time
is that every neighbour's `protected_spec` folds into `effective_mask`
unconditionally in both directions, and the claims are real —
`base-os-ubuntu-noble` protects `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`,
`/etc/pam.d/**`, `sshd_config`; `powernode-system-base` protects the agent binary
itself; `hub-backend` protects `master.key`. But those are build-time, by
convention, and scoped to the target node's assignment set. Residual risk is the
same one repo modules carry minus review — unprotected paths such as
`/etc/systemd/system/*.service` or anything on `PATH` — mitigated by the diff
preview and promotion gate, and worth a follow-up to broaden `protected_spec`
claims.

## Lifecycle without a repo

Most of what a repo provides is already built elsewhere:

| Repo affordance | Replacement | State |
|---|---|---|
| Diff to review | `ModuleDiffService` (spec/package/mount diff + stable fingerprint; wired for UI preview, Concierge, rolling-upgrade disclosure) | exists; diffs **specs**, not content — content diff becomes trivial once content is stored |
| History | `NodeModuleVersion` auto-versioning on any spec/`data_checksum` change, with changelog + `version_number` | exists; needs the content store to be meaningful |
| CI | the builder lane itself (deterministic build + ingest verification); `ModuleBuildParityService` for dual-run comparison | exists |
| Rollback | **better than rollback-to-commit**: each version's artifact is content-addressed and stays pullable, so `rollback_to!` / `promote_to_version!` converges agents next tick with no rebuild | exists |
| Approval before compose | `built → staging → blessed → live` with legal-transition enforcement; `Fleet::ModulePromotionService` runs only after the autonomy gate (`system.module_promote_to_live` = `require_approval`, 4h TTL) + `ModulePromotionSensor` | exists |
| Audit | FleetEvents per publish/commit (`module.version.committed` carries `committer_instance_id`; `system.module_published`) | exists |

**One wiring defect to fix alongside.** `promotion_state` and
`current_version_id` are parallel lifecycles: `ModulePublicationProcessor`
auto-promotes `current_version` on publish regardless of `promotion_state`. The
design must connect them (see decisions below).

## Open decisions for the operator

These are policy, not engineering, and should be settled before implementation:

1. **Per-module key pinning** — adopt the materializer-key split and enforce
   pinning on both ingest paths? Without it, platform-authored and repo-built
   artifacts are indistinguishable to a verifier.
2. **Promotion asymmetry** — recommended: platform-generated dependants
   auto-promote (the permissioned DB edit *was* the operator action), while
   operator-authored non-dependants and agent commits stay `built` + gated. This
   asymmetry should be explicit rather than emergent.
3. **Control-plane generation fallback** — persistent builder for ops-hub, or
   `erofs-utils` + `fsverity` on the hub stack?
4. **`CopyPath`** — delete across agent/serializer/model/UI, or correct the
   misleading comments and leave the field?

## Verified vs inferred

**Verified by reading code:** the two build lanes and the package lane's
repo-less header; `PackageBuildHandler` registration; `set_data_file` dropping
its content argument and having no callers; `AgentModuleCommitService` discarding
the tar; `commit_cmd`'s deny list; the variety position offsets and their "in the
union" comment; `file_spec` delegation; `protected_spec` bidirectional masking;
`verify.AlwaysOK` wiring and its unconditional `nil`; `CopyPath` declared and
never read; `log-forwarder-vector` as the only module with a non-empty
`dependency_spec`; `create_dependant!` having no callers.

**Inferred, not probed:** ops-hub's tool inventory (from module composition, not
a live check) — in particular the absence of `mkfs.erofs`; the `mount(2)` option
page limit (kernel knowledge, not measured on this fleet). Both should be
confirmed before relying on them.
