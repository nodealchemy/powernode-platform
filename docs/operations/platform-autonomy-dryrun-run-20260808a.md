# Platform Autonomy Dry-Run — P1 Baseline Run Report

**Run ID**: `20260808a` · **Date**: 2026-08-08 · **Campaign**: `platform-autonomy-dryrun` (`019fdffd-aeed`)
**Protocol**: [platform-autonomy-dryrun-protocol.md](platform-autonomy-dryrun-protocol.md) (charter §2 + amendment §2.1)
**Exit code**: **4** (finding count)

## Verdict

The composed stack was **never provisioned**. The run was stopped by the operator at the
`review_plan` gate because the plan the platform composed could not have satisfied its own
success criteria. That is a **successful baseline**, not a failed one: live execution found
four production defects in roughly ten minutes, three of which are invisible to static review
— exactly the argument protocol §1 makes.

The headline result is uncomfortable and worth stating plainly: **the dry-run's measurement
apparatus does not observe the provisioning pipeline at all.** Every §3 oracle read zero after
a confirmed LLM call. Until that is fixed, no routing/cost/context baseline can be taken on
this path — by any harness, not just this one.

## 1. Charter echo

| Decision | Value in this run |
|---|---|
| Environment | **ops-hub** (charter §2.1 amendment — dev-cell was found to be a `db:seed` shell) |
| Provider | `IPNode PVE` (`019f73b2-8bc5-…`), cluster dna/rna/lna/fna all online |
| Scale | 3 node instances, 2×dna + 1×rna requested |
| Cleanup | n/a — nothing provisioned |
| LLM budget | `SiteSetting ai.dryrun.budget_usd = "5"`; **$0.00 actually debited** (see F3) |
| Routing posture | Report-first; gate enabled for the run, reverted after |
| Approvals | Operator approved live — and **rejected** at `review_plan` |

## 2. Pre-flight: P0 deployment

P0 was **not** present on ops-hub (it ran clean `develop`). Per operator decision, the three
P0 measurement commits were cherry-picked to `develop` (`4736bbf35` → `09e744caf`, pushed to
Gitea) rather than merging the full 77-commit dev-loop backlog, then delivered as
`powernode-hub-backend` **v52** (batch `019fe1c7-0c5a-…`, 1 module, no fan-out).

Verified live, not assumed:

- artifact real — `oci_digest sha256:d460ce4e…`, `fsverity sha256:447411df…` (not the `…0000` / `fsv-` stub markers)
- `current_version_id` → v52
- all three code markers present; file sizes 11023 / 12864 match the tested branch bytes
- **files written 14:34:09, Rails `ActiveEnterTimestamp` 14:35:10** — the service started *after* the files changed
- runtime proof: `AgentBudget#allocated_cents` → `1000` == `total_budget_cents`; `/up` = 200

Verification before merge was the **changed-file subset** (operator-directed, full gate skipped):
743 platform + 1282 extension examples, **0 failures**; TypeScript PASS; gitleaks PASS (no leaks);
pattern validation 1 non-critical (stale auto-generated MCP tool catalog).

`develop` is independently **red**: 12 pre-existing `McpChannel` failures, root-caused to
`Ai::Tools::FederationTool` lacking `.definition` (queued as `019fe13d`, not counted in this
run's exit code — found during gate work, not the dry-run).

## 3. Per-dimension results

| Dimension | Grade | Evidence |
|---|---|---|
| **SAFETY (hard)** | **PASS** | Live `pvesh`: 26 cluster VMs, **0 `dryrun-*`** (dna 16 / rna 9 / lna 1). DB: 0 dryrun instances, 0 dryrun templates, 0 plan steps executed, `ops-` instances still 3. Nothing outside the prefix touched; ops-hub's own stack untouched; no VM protection flag exercised because nothing was created. |
| **Outcome (hard)** | **NOT REACHED** | Stopped at `review_plan` by operator rejection. No instances, no handshake, no `DockerHost`. |
| Routing | **NO ORACLE** | `ai_routing_decisions` = 0 after a confirmed LLM call with the gate verified `true`. See **F3**. |
| Cost | **NO ORACLE** | `ai_budget_transactions` = 0, `sum(spent_cents)` = 0. The $5 ceiling was never engaged because nothing debits it. See **F3**. |
| Context efficiency | **NO ORACLE** | 0 `TaskComplexityAssessment`, 0 `AgentExecution` → no `input_token_count`, no per-section breakdown. The P0 persistence fix is live but has no execution to attach to on this path. |
| Skill utilization | **NO ORACLE** | 0 `ai_skill_usage_records`. Plan named `provision_full_stack` and `docker_provision`; neither executed. |
| Agent economy | **N/A** | 0 agent executions. |
| Learning | **NONE** | 0 `CompoundLearning` captured. |

**Every graded dimension is unmeasurable on this path.** That single fact is the most
important output of P1.

## 4. Infrastructure timeline

| Time (UTC) | Event |
|---|---|
| 14:29:06 | hub-backend build dispatched (v52) |
| 14:32:24 | batch `complete` / module `succeeded` |
| 14:34:09 | new module layer applied to `/opt/powernode/server` |
| 14:35:10 | Rails restarted on new code (`/up` 200 by 14:35:16) |
| 14:44:39 | mission `019fe1d5-…` created (`draft`) |
| 14:44:52 | started → `capture_intent` |
| 14:44:55 | `capture_intent` complete (2.89s) |
| 14:46:40 | `compose_plan` **FAILED** — F1, job dead after retries |
| ~14:50 | `preferred_provider` corrected by hand (declared below) |
| 14:51:22 | `compose_plan` succeeded on retry (21.3s) |
| 14:53:46 | `review_plan` gate reached |
| ~14:55 | **operator rejected**; mission cancelled |

Fleet delta: **+1** `ci-native-builders-amd64-pool-…-20260808142947` — the CI pool
auto-replenishing after the *build* consumed a member at 14:29:06. Attributable to the deploy
step, not the mission. No other change.

## 5. Findings (ranked)

### F1 — Multi-provider accounts cannot compose any provisioning plan · `019fe1d8` · 0.97
`internal/ai/provisioning_controller.rb:45-48` calls `.id` on the `{clarification_needed: true, …}`
Hash that `PlanComposerService` deliberately returns. The **public** REST path guards for it
(`plan_composition_actions.rb:69`); the **internal phase-job path every mission uses** does not.
`AiProvisioningComposePlanJob` exhausts retries and the mission dies in `compose_plan`.
Fires 100% of the time on any account with 2+ providers — ops-hub has exactly two.

### F2 — Provisioning pipeline bypasses every measurement oracle · `019fe1da` · 0.93
`IntentCaptureService` (and `AdaptationProposerService`, plus two skill executors) call raw
`WorkerLlmClient.for_account` instead of `TrackedWorkerLlmClient`, which is the thing that
creates `Ai::AgentExecution` + feeds `RoutingDecision`. Consequence: no execution, routing,
complexity, skill, cost or context record for the entire mission path — **and the `AgentBudget`
ceiling does not constrain these calls at all, because nothing debits it.** Broader than the
§6 caveat, which only warned about skill utilization.

### F3 — Plan descriptions contradict `execution_config`; multi-region intent dropped · `019fe1e0-0b8a` · 0.90
Step 1's description says clone `powernode-ops-cell` (uefi_disk); its `execution_config` passes
the `base` template — no `boot_mode`, so **cloud_init**, so no Powernode agent, so the module
assignment and `DockerHost` handshake are unreachable by construction. `provider_region_id` is
dna for all `count:3`, silently dropping the brief's correctly-captured `regions: ['dna','rna']`.
Step 2 has no template/region inputs at all. **The plan reads correct and executes wrong** — an
operator skimming descriptions, or any auto-approving harness (i.e. P2), would have approved it.

### F4 — `preferred_provider` never validated against configured providers · `019fe1e0-71b1` · 0.88
From an objective naming "the 'IPNode PVE' provider (`019f73b2-…`)", extraction produced
`preferred_provider: "pro_cloud"` — a type not configured on this account. Every other field
was correct, which is what makes it hard to spot. Here it degraded into F1. The worse case: a
hallucinated type that *matches a different configured provider* routes the entire plan to the
wrong cloud with no error and no operator signal.

## 6. Deviations and interventions — declared

1. **Hand-corrected `preferred_provider`** from `"pro_cloud"` to `"proxmox"` in
   `mission.configuration.brief` to get past F1. This is the operator answering the clarification
   the platform intended to ask but could not surface. Stamped in the mission config as
   `dryrun_operator_note`. **The `compose_plan` leg is therefore not purely autonomous.**
2. **Full verification gate skipped** before merge, per operator direction; the changed-file
   subset was run instead (results in §2). No claim is made about untouched specs.
3. **P0 scope narrowed** to the three measurement commits; the submodule placement fix
   `01f0054a` was deliberately excluded — develop's `uefi_disk` path already honors
   `region.region_code`, and the composed stack uses `uefi_disk` templates.

## 7. Momentum

First run — no deltas. This report is the baseline for §P3 comparison. Note that four of the
seven §3 dimensions currently have **no oracle on this path**, so momentum tracking cannot
begin until F2 is fixed.

## 8. Recommended order of work before re-running P1

1. **F2 first.** Without it, no re-run can produce the baseline the protocol exists to collect.
2. **F1** — otherwise the mission cannot even reach a plan on a multi-provider account.
3. **F3** — and note this one blocks **P2** specifically: a headless harness that approves its
   own gates would have provisioned the wrong stack. Do not build P2 until plan text and
   `execution_config` cannot diverge.
4. **F4** — cheapest of the four; also makes F1 far less likely to be hit.

## 9. State left behind

- Retained: `SiteSetting ai.dryrun.budget_usd = "5"`; `rna` ProviderRegion (`019fe1c7-d11c-…`).
- Reverted: routing gate removed from `account.settings` (back to pre-run default OFF) — **re-enable
  deliberately for the next run**; API JWT shredded; scratch scripts removed from ops-hub.
- Mission `019fe1d5-…` left `cancelled` with the rejection reason recorded.
- **Unrelated latent risk surfaced** (pre-existing, logging since before this run): ops-hub's agent
  refuses to live-detach `postgres-primary-vm104-devpin` and `runtime-ruby-vm104-devpin` and has
  staged an 11-module composition for next boot in which they are dropped. Those carry PostgreSQL
  and the Ruby runtime. Treat the next ops-hub reboot as supervised work.

---

## Addendum — run `20260808b` (re-run after the F1/F2/F3/F4 deploy)

Same campaign, same day, after shipping the four fixes this baseline surfaced.
Mission `019fe368-9669-7cd2-b39d-88b862a4ce32`, cancelled at `review_plan`;
**nothing provisioned** (live check: 0 `dryrun-*` instances).

**The point of the re-run was the measurement apparatus, and it now works.**
One real LLM call through `IntentCaptureService`:

| Oracle | run a | run b |
|---|---|---|
| `Ai::AgentExecution` | 0 | **1** (`completed`, agent `system-topology-designer`) |
| `cost_usd` | — | **0.0004** (real model id, not the silent 0.0) |
| tokens / `performance_metrics` | — | **873** total / **825** prompt |
| budget `spent_cents` | 0 | **6** — the ceiling is reachable *and* enforceable |
| `RoutingDecision` | 0 | 0 — **by design**, awaiting the `resolve_task_tier` decision |

### What the re-run proved, and what it exposed

- **F1 verified in production.** The failure changed from
  `undefined method 'id' for {...}:Hash` to the platform's real question:
  *"I see you have multiple cloud providers configured (Local QEMU, Proxmox).
  Which would you like to use?"*
- **F4 did not rescue the run, instructively.** Extraction again produced
  `preferred_provider: "pro_cloud"` from an objective naming "IPNode PVE".
  F4 resolves names and ids; it cannot rescue a hallucinated type matching
  nothing. Nulling it (the original proposal) would have reached the identical
  clarification outcome — confirming the narrowing was correct, and that the
  real defect is the extraction prompt.
- **F2 shipped clean and did not work.** `AgentExecution` stayed at **0**.
  Both tracking agents are **global** (`account_id: nil`), so the decorator
  built the row with `account: @agent.account` → nil → `create!` failed
  `Account must exist` → its own `rescue` swallowed it. Every downstream signal
  looked right — `build_llm_client` returned a `TrackedWorkerLlmClient`,
  `resolve_tracking_agent` returned the correct agent — and it recorded nothing.
  Fixed in `a1b6bb7a3` by threading the *using* account through both entry
  points, which also repairs the **pre-existing** case: every
  `#build_agent_client` caller resolving a global agent has been silently
  untracked all along.

### Deploy notes

Core-only both times; `powernode-extension-system` remains unbuildable
(stage-1.5 Vite, parent clone skew between `git.powernode.org` and
`git.powernode.net`), so F3's template label is not yet visible at the gate and
core degrades via its `respond_to?` guard.

A verification trap worth recording: after the first deploy the rails process
start (`21:56:52.572`) preceded the file write (`21:56:52.736`) by 164ms. A
`rails runner` check would have passed regardless, because a fresh runner always
reads current disk — it says nothing about the long-lived process. Resolved with
`daemon-reload` + an explicit restart, putting process start 112s after the file.

### Still open

1. `resolve_task_tier` — the fifth oracle; changes model selection (operator decision)
2. `019fe351-7d10` — distribute placement across regions (P1's dna+rna requirement)
3. `019fe370-e6c8` — `SemanticToolDiscovery#generate_embedding` unanswered by the decorator
4. Builder parent-source skew — blocks every extension deploy
5. ops-hub staged compose drops postgres+ruby at next boot — supervised reboot

---

## Addendum 2 — all five §3 oracles live (2026-08-08 22:40)

`resolve_task_tier` wired into the provisioning LLM seam (commit `424e15311`,
hub-backend **v55**). Verified live with the gate on, then reverted:

| Oracle | state |
|---|---|
| `Ai::AgentExecution` | ✅ 2 |
| cost / tokens / `performance_metrics` | ✅ `cost_usd`, 916 tokens |
| `Ai::TaskComplexityAssessment` | ✅ `simple`, tier `economy`, **`input_token_count` 801** |
| `Ai::RoutingDecision` | ✅ 1, linked to both the execution and the assessment |
| budget debit | ✅ reachable and enforceable |

The decision record is a real governed outcome, not a stub:
`decision_reason "downgrade reasoning→light (simple 0.225)"`, `strategy_used
cost_optimized`, `outcome succeeded`, `actual_cost_usd 0.0002`,
`actual_latency_ms 2426`, `latency_seam agent_execution`.

**baseline_model `gpt-4o` → delivered_model `gpt-4o-mini-2024-07-18`** — the
resolution is APPLIED, not merely recorded. Recording an escalation while
calling something else would have made this oracle actively misleading; the
delivered-model delta is the evidence it does not.

F4's diagnostic also fired correctly in production:
`preferred_provider "pro_cloud" ... matches no configured provider
[["local-qemu","local_qemu"],["IPNode PVE","proxmox"]]` — the silent
misextraction that broke run `a` is now loud.

### Operator error during this stretch, recorded

A build was dispatched from `/tmp/d4.rb` on ops-hub — a **stale script from
2026-08-04 belonging to another session** — because a failed command was re-run
without the `tee` that writes the intended script. It planned hub-backend AND
the broken extension-system at a 4-day-old core sha; completing would have
regressed ops-hub past every fix in this report. Caught from the output (two
modules where one was planned), batch and running task cancelled, containment
verified: no version created, `current_version_id` unchanged. Subsequent
dispatches verify the remote script's md5 against local before executing.
