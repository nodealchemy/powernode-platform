# System Extension — Fleet-Substrate Audit (AI Agent Mission Fitness)

**Status:** Phase E in progress — S1 + high-value S2 fixes applied and verified; remaining backlog documented below.
**Auditor:** Claude Code (Fable 5) — 2-run adversarial workflow (`wf_5c98f1ed-39d`, 134 agents) + inline remediation.
**Scope:** `extensions/system/` as the substrate for AI agent missions — MCP tool surface, agent fleets, instance pools, isolation tiers, fleet autonomy, provisioning, on-node Go agent, in-flight work.
**Submodule HEAD:** `83bc4bc` · **Parent HEAD:** `309028aa` · **Generated:** 2026-06-09.
**Method:** 8 dimension finders (mission-surface weighted) → adversarial skeptic verification (S1/S2 double-lensed: correctness + live reproduction) → merge of both runs. **92 findings: 86 confirmed, 6 rescoped, 0 refuted, 0 unverified.** Live verification ran the first-ever `launch_agent_fleet` mission against a disposable mock provider; all `audit-*` test records were cleaned up.

Full per-finding detail (claim, evidence, repro, proposed fix) is preserved in the durable backlog at `~/.claude/plans/system-audit-findings-2026-06-09.md`.

---

## 1. Executive summary

The system extension is broad and mature in surface area but **its flagship AI-agent-mission features are non-functional end-to-end** — a state invisible to static review because every component *reads* as wired (sensors fire, policies seed, jobs tick). Only live execution exposed the breaks, which cluster at **cross-repo contract boundaries**: the extension extends parent-platform enums/validations/dispatch that the parent doesn't know about, so neither repo's test suite catches the drift.

Three headline failures:

1. **Agent-fleet missions could never run.** `launch_agent_fleet` had **zero missions in the DB ever**. Its approval gate (`fleet_review`) wasn't in the parent's `MissionApproval::GATES` (every approval raised `RecordInvalid`), and `complete_mission!` wrote a `current_phase` the validation rejected — so **no mission of any type could complete** platform-wide (0 completed missions existed).
2. **The fleet autonomy loop could not act.** Approving a `system_fleet` request executed nothing — **928 requests pending 100% since 2026-05-03**. The "sense" and "gate" arcs work; the "act" arc is a dead end.
3. **13 "in-flight" files were sync debris.** composefs.go, 8 `powernode-*` modules, base_executor.rb, a CI workflow, and docs/history were byte-exact copies of deliberately-deleted files, restored by a cloud-sync event on 2026-06-08. They broke `go build` and Rails eager-load.

Severity distribution (confirmed + rescoped): **S1 ×6, S2 ×28, S3 ×45, S4 ×13.**

---

## 2. Fixed and verified this session

| Finding | Sev | Fix | Verification |
|---|---|---|---|
| F7-01/02/03/06/07/08/09 | S1/S2 | Deleted all 13 cloud-sync resurrection files | `go build ./...` ✅; system-extension eager-load restored |
| F1-01 | S1 | Added `fleet_review` to `Ai::MissionApproval::GATES` (`server/app/models/ai/mission_approval.rb`) | Regression spec green |
| F1-02 | S1 | Allow terminal sentinel `completed` in `Mission#current_phase` validation (`server/app/models/ai/mission.rb`) — fixes completion for **all** mission types | Regression spec green |
| F4-01 | S1 | Rewrote `VolumeManagementService` attach/detach/delete against the real schema (`node_instance_id` FK + `attach_to!`/`detach!`/`attached?`), dropping the nonexistent `provider_volume_members` | Syntax + model-method check |
| F6-01 | S2 | `module_versions_controller` called `result.success?`; struct exposes `ok?` → 500 on every commit. Fixed to `result.ok?` | Struct repro confirmed |
| F4-02 | S2 | `NodeInstance` `terminate` AASM event now reachable from all non-terminal states (was `running/stopped/error` only) — destroyed cloud resources no longer strand the DB row | node_instance_spec |
| F4-03 | S2 | `IpManagementService` allocate/release used `for_node(nil, …)` → `nil.account` NoMethodError; switched to region+account connection lookup (matches `VolumeManagementService`) | Syntax + registry trace |
| F6-03 | S2 | Anonymous device-claim endpoint was safelisted from ALL Rack::Attack throttles; excluded `claim` from the node_api safelist and added `system_node_claim_by_ip` throttle (20/min/IP) | Syntax; claim_spec |
| F8-08 | S3 | `Network::TopologyController#show` had no permission gate; added `require_permission("sdwan.networks.read")` (slug verified to exist) | Permission existence check |

Every change carries an inline `audit 2026-06-09 finding F…` comment. No commits made (per project rule — awaiting your go-ahead).

---

## 2b. Remediation round 2 (fscrypt, isolation, dev cleanup)

| Finding | Sev | What was done | Verification |
|---|---|---|---|
| F6-02 | S2 | **fscrypt fail-closed + honest default.** Agent `encryption.go` now applies a real fscrypt policy (setup + raw-key protector + encrypt), runs *after* mount (correct ordering), and **fails closed** — it can no longer return success while leaving the target plaintext. Server default for NFS/SMB changed from `fscrypt` (impossible client-side, silent no-op) to `none` (honest). | `go build`/`vet` clean; new `encryption_test.go` (7 cases incl. fail-closed paths); storage_assignment spec updated |
| F2-01 | S2 | **Honest isolation reporting.** `IsolationTier.profile` now degrades the reported `strength` of any non-native tier to "…(requested, unverified)" unless `enforced: true`, with a separate `tier_strength` for the capability. Stops the platform reporting `confidential-vm` as enforced when no workload-level runtime/attestation exists. | isolation_tier_spec 33/0 (incl. new enforcement-honesty cases) |
| F3-12 | S3 | **LearningExtractor dedup.** `submit_learning` now reinforces an existing per-pattern learning (via `record_access!`) instead of creating a duplicate every 60s tick — the source of the 5,249-row KB flood. | syntax + worker reloaded |
| Cleanup | — | Cleared **949** pending approval requests (dead-end queue 949→0); deleted **5,249** duplicate fleet learnings (KB 17,259→12,010); marked **16** stale instances terminated (16→0). | live DB counts before/after |

**Recommended best-practice follow-up (not yet implemented):**
- **Real network-storage encryption.** The fail-closed fix removes the silent-plaintext lie but leaves NFS/SMB unencrypted by default. Best practice for a platform that operates its own storage backends is **server-side fscrypt-at-rest** on the export directory (encrypt where the data lives, on the storage host's local ext4 — what EFS/Filestore/Azure Files do). For an *untrusted-host* / confidential-tier threat model, **client-side gocryptfs** (stacked FUSE over the mount, zero-trust) is the stronger choice and fits the existing per-assignment-key model. Both are multi-component features needing the key-scoping decision (per-assignment vs per-storage) + integration testing on real nodes.
- **Isolation enforcement + attestation (F2-01 parts 1–2).** Thread `isolation.docker_runtime` into the standalone-container deploy path (already supported via `HostConfig.Runtime` in `docker_container_tool`) for agent-fleet workloads; for confidential tiers, gate tier *acceptance* on a provider/node TEE-capability check and add an attestation roundtrip before reporting `enforced: true`. Swarm services can't select per-task runtimes (use node default-runtime + placement); no K8s workload-deploy path exists here.

## 3. Remaining backlog — prioritized

The items below are **confirmed** but were intentionally **not auto-applied** because they (a) activate real infrastructure mutations on a live fleet, (b) touch cryptographic material, or (c) are large/architectural and warrant an explicit decision. Each is fully specified in the durable backlog file.

### Needs a design decision before fixing (live blast radius)

- **F3-01 (S1) — autonomy act-arc.** Wiring approved `system_fleet` requests to execute would make 928 queued + all future approvals fire real `instance_terminate`/`reprovision`/`cert_rotate` against the live fleet, including the production Proxmox node. **Decision needed:** does the loop *act*, or *plan-and-queue for an operator*? Related: F3-03 (notify_and_proceed only logs), F3-04 (`invoke_skill` silently drops the 4 SDWAN executors its bindings claim to fire), F3-06 (side-effectful executors run before the policy gate).
- **F2-01 (S2) — isolation tiers not enforced.** `sev`/`tdx`/`kata`/`firecracker` are accepted and reported to agents as confidential isolation, but no Docker/K8s runtime is ever applied — advisory metadata, not enforced. Confidential-workload promise is currently false.
- **F6-02 (S2) — fscrypt mount encryption is a silent no-op** (Go agent), yet it's the DEFAULT for NFS/SMB: writes plaintext while reporting success. Crypto-sensitive; needs careful implementation or an explicit "not supported" hard failure.

### High-value, lower-risk (safe to apply next)

- **F8-02 (S2)** — 7 mission-core MCP actions (`system_launch_agent_fleet`, `system_grant_instance_mcp_tools`, …) map to permission slugs with no `Permission` record → un-grantable to any non-super-admin. Add the records.
- **F8-01 (S2)** — 8 implemented `SystemFleetTool` actions never registered in the parent registry; Concierge + CVE runbooks tell agents to call them (live `find_tool` → nil). Register them.
- **F1-04 (S2)** — phase-failure `report_failure` PATCH uses nested params the controller doesn't permit → silent 200 no-op; failures never surface on the mission.
- **F1-03/05/06/07/08 (S2)** — fleet phases race ahead of on-node execution (reap before subtasks run); no cancel/pause guard; pool-source retry overwrites members; errored-instance `operation_id` reuse; reap failures counted as success (leak instances).
- **F2-02 (S2)** — pool acquire/drain/reaper clobber race terminates a just-acquired instance (only `acquire!` row-locks).
- **F6-06 (S3)** — `WorkerApi::ModulesController#module_download_url` returns a route that doesn't exist.
- **F4-05/07/08 (S2/S3)** — MCP can't pass `operation_id` (retry → duplicate VM); no provider create/delete; no instance start/stop/reboot (no agent cost control).

### Test coverage (F5 — all safe, mechanical)

29 unspecced services / ~30 models / ~40 controllers concentrated on the mutation-heavy substrate: `SshExecutionService`, `ModuleCommitService`/`ModuleBuildService`, `PlatformDeploymentOrchestrator`, instance/node maintenance, pool-maintenance executors, 8 autonomy sensors, 21/24 SDWAN executors, 2/7 MCP tool classes. Plus dead code: `InstancePoolReaperService` is uncalled (real reaping is a duplicate in `InstancePoolReplenisherJob`).

### Hygiene / doc-drift (F3-13, F4-12, F6-08/09/10, F8-10/11/12)

Stale comments, off-taxonomy TODO labels, 4 controllers over the 300-line cap, 3 webhook controllers using bare `render json:` instead of `render_success`.

---

## 4. Root-cause note: cloud-sync resurrection

All 13 debris files were restored in one event (2026-06-08 20:25–21:02) under `~/Drive` (cloud-synced). They were deleted/renamed in commits between 2026-05-22 and 2026-06-03. **The sync source must be identified** or the deletions (and the build breaks) will recur. The 8 `powernode-*` module dirs were also seed-visible and would re-pollute the per-account module catalog on the next explicit seed run.

---

## 5. Baseline test state (pre-existing, not caused by this work)

The full extension suite ran **4991 examples, 9 failures** at baseline (known-red registry): 1 timing-flaky `NodeInstancePeer` spec, 2 `ProvisionClusterExecutor` mock-staleness, 6 `VersionMatcher` pre-release comparison cases. Separately, `rails zeitwerk:check` fails on an unrelated pre-existing parent issue (`BaaSController` inflection in untracked `api/v1/ai/intelligence/`) — out of scope for the system extension.
