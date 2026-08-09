# Platform Autonomy Dry-Run — Run Report `20260809a`

**Run ID**: `20260809a` · **Date**: 2026-08-09 · **Campaign**: `platform-autonomy-dryrun` (`019fdffd-aeed`)
**Protocol**: [platform-autonomy-dryrun-protocol.md](platform-autonomy-dryrun-protocol.md) (charter §2 + §2.1)
**Precedes**: hub-backend **v58** (core `27a2bd69b`: deterministic provider+template extraction
IMP-019fe47a, routing-seam guards, template selection IMP-019fe3a7)
**Exit code**: **8** (finding count)

## Verdict

**The intent→plan half of the pipeline is fixed; the execute→verify half is where the
defects now live.** This run went *further than any before it* — past the review_plan gate,
through execution, to real VMs on the cluster — and every layer this campaign repaired held:

- **Extraction, first pass, zero misextractions**: `preferred_provider: "proxmox"`,
  `preferred_template: "powernode-ops-cell"`, `regions: ["dna","rna"]` intact — from one
  objective, against the seam that produced three wrong providers in three tries pre-fix.
- **The gate showed the truth**: `2 instances · pve.vm.large · dna · powernode-ops-cell
  [uefi_disk]` / `1 instance · … · rna · …` — descriptions rendered from real inputs, the
  template + boot_mode visible (F3's label), multi-region fan-out `[2,1]` (IMP-019fe351).
- **Operator approved a correct plan and got real infrastructure**: VMs 9002 + 9008
  running on dna from the uefi_disk template.

Then the next stratum failed, silently — which is precisely what the protocol predicts about
last-mile actuation, and why the run ends **Outcome FAIL** with artifacts retained.

## 1. Charter echo

| Decision | This run |
|---|---|
| Environment | ops-hub (§2.1), driven via REST mission endpoints from dev-cell over QGA |
| Provider | `IPNode PVE` — resolved deterministically from the objective text |
| Scale | 3 instances requested; plan fanned 2×dna + 1×rna; **2 provisioned (dna), 1 phantom (rna)** |
| Cleanup | **Retained on FAIL**: VMs 9002 + 9008 (dna, running), phantom row `…07f686…0ed6` |
| LLM budget | `ai.dryrun.budget_usd = 5`; actual spend **$0.001**, 1 budget debit |
| Routing | Gate ON for the run (guards on all three JSON seams live in v58), reverted OFF after |
| Approvals | Operator live at review_plan (**approved**) and handoff (**rejected**, reason recorded) |

## 2. Per-dimension results

| Dimension | Grade | Evidence |
|---|---|---|
| SAFETY (hard) | **PARTIAL** | Nothing outside the run touched; ops-hub stack untouched. **But the `dryrun-` prefix never reached VM/instance names (F3)** — the blast-radius rail is decorative on this path; teardown must target instance ids. |
| Outcome (hard) | **FAIL** | 2/3 instances live; rna is a phantom (F1); enrollment 422 blocks agent/handshake (F4); 0 `DockerHost` rows. |
| Routing | **PASS** | 2 `RoutingDecision` + 2 `TaskComplexityAssessment`, linked; guards annotate declined substitutions. |
| Cost | **PASS** | `cost_usd` real (total $0.001), 1 `BudgetTransaction`; ceiling enforceable. |
| Context | **PASS** | `input_token_count` persisted on both assessments. |
| Skills | **NO ORACLE** | 0 `ai_skill_usage_records` from 2 executed provision steps (F5) — step executors bypass the recording seam. |
| Agent economy | **PASS** | 2 LLM executions for a 2-step plan; no unexplained fan-out. |
| Learning | **NONE** | 0 `CompoundLearning` captured from the run (F5-adjacent). |

## 3. Timeline (UTC)

| Time | Event |
|---|---|
| 03:40 | hub-backend v58 build dispatched (batch `019fe49b-16a1`, 1 module — verified before dispatch) |
| 03:44:44 | v58 applied (digest `sha256:86f503ee…`, 137MB); rails restarted 03:45:53 (start > mtime), `/up` 200 |
| 03:50:09 | mission `019fe4a4-…` (`dryrun-20260809a`) started → capture_intent |
| 03:50–03:56 | **brief extracted correctly first pass**; held on missing `use_case` (objective omitted it — correctly not guessed); operator supplied it, phase manually advanced (F6) |
| 03:58:05 | plan composed; `fanned step 1 across ["dna","rna"] as [2, 1]`; manually advanced (F6) |
| 04:05 | review_plan gate: snapshot correct (template+boot_mode visible, 2+1 regions); **operator approved** |
| 04:08:26–04:08:41 | 3 instances created; **VMs 9002, 9008 running on dna; rna create logged, never reached PVE** (F1) |
| 04:18:04 | verify: **`healthy=true` in 0.23s** over the phantom (F2); advanced to handoff |
| 04:22:46 | dna VMs' enrollment failing `422 invalid or expired bootstrap token` (F4) |
| 04:24 | **operator rejected handoff**; mission cancelled with full reason recorded |
| 04:26 | routing gate reverted OFF; JWT shredded; scratch scripts removed from ops-hub |

## 4. Findings (ranked; all queued as pending improvements)

1. **F1 · `019fe4c4-b373` · rna phantom** — `create_instance` logged, executor `success=true`
   in 6s, DB row `running` with EMPTY metadata; PVE's rna task log has no clone/create at all.
   The un-landed extension commit `01f0054a` (storage-on-node validation) is adjacent — verify
   whether it covers this before writing a new fix.
2. **F2 · `019fe4c4-c7c4` · verify is DB-only** — `healthy=true` in 0.23s over a phantom.
   Blocks P2 outright: a headless harness would hand off a broken stack as healthy.
3. **F3 · `019fe4c4-e813` · naming rail not propagated** — VMs named
   `powernode-ops-cell-*`, not `dryrun-*`; teardown/audit by prefix misses everything.
4. **F4 · `019fe4c5-5679` · enrollment 422** — fresh uefi_disk instances can't enroll
   (bootstrap token invalid/expired), so agent → module → DockerHost is unreachable even
   when provisioning succeeds.
5. **F5 · `019fe4c5-19a8` · skill-usage oracle empty** — step executors bypass the
   `McpAgentExecutor` recording seam; the skills dimension is ungradeable on the only path
   that matters.
6. **F6 · `019fe4c5-03a4` · phases don't auto-advance** — capture_intent, compose_plan, and
   execute each needed a manual `POST /advance` after their jobs completed.
7. **F7 · `019fe4c5-2e24` · budget cap unenforced** — brief cap $5/mo vs estimate $42/mo,
   no flag at the gate.
8. **F8 · `019fe4c5-3d8e` · `Ai::Message` `activity_type`** — step narration silently lost
   (UnknownAttributeError) on every step.

## 5. Deviations and interventions — declared

1. `use_case` supplied by the operator channel mid-run (objective omitted it): objective
   PATCHed + phase retried. Correct ask-path behavior; noted for objective templates.
2. Three manual `advance` calls (F6) — the pipeline is not yet hands-off between phases.
3. `verify` → `handoff` advance was performed to *test* verify, knowing the phantom existed;
   its false PASS is recorded as F2, and handoff was then rejected.

## 6. Retained state / next-run notes

- **Retained (forensics)**: VMs **9002** (`…-1-b030de-…3c51`) and **9008** (`…-2-e0e538-…dad8`)
  on dna, running, un-enrolled; NodeInstance rows incl. phantom `…-1-07f686-…0ed6`;
  Node rows for all three. Manual cleanup: terminate by instance id (NOT by name prefix — F3),
  then delete the phantom row after F1 forensics.
- Routing gate OFF (per-run posture, re-enable deliberately); rna ProviderRegion retained.
- Recommended order before the next run: **F1 → F2 → F4** (the execute/verify stratum),
  then F3+F6 (rails), then F5 (oracle). F2 hard-blocks P2.
