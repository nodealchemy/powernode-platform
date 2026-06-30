# Loop Engineering Parity Analysis

**What this is:** a capability comparison between Powernode's autonomous-loop / campaign
substrate and the external **"Loop Engineering"** framework popularised by Codez
([@0xCodez](https://x.com/0xCodez/status/2064374643729773029), 9 Jun 2026 —
*"Loop engineering: the 14-step roadmap from prompter to loop designer"*).

**Why:** the article codifies the industry shift "from typing prompts to designing the loop
that prompts." Powernode is, in effect, a *productised* version of exactly that thesis
(`Ai::RalphLoop`, `Ai::Campaign`, the `/dev-loop` + `/improve` + `/campaign` harness). This
doc maps the framework point-by-point onto what actually ships in this repo, so we can see
where we are **ahead**, at **parity**, or have a real **gap** — and drive the gaps as a
campaign.

> Audit-only artifact. No code changed to produce it. Findings are tracked for closure by the
> **Loop Engineering Parity** campaign (see [Driving the gaps](#driving-the-gaps)).

Date: 2026-06-29. Branch: `develop`. All file references verified against the working tree.

Related platform knowledge: *"Loop-engineering pattern catalog (2026)"* (`019eb378-a423-740f-855f-dc2f5f7c1268`)
already maps the external loop canon (Ralph / evaluator-optimizer / plan-execute-verify / ReAct)
onto Powernode primitives; this doc is the **gap-focused** companion to it.

---

## TL;DR

Powernode has **built nearly the entire framework**, and in places exceeds it (DB-backed state
beats flat JSON; ~540+ MCP tools; skill evolution/composition; per-campaign worktrees with
isolated test DBs). The systemic weakness is the same one the framework warns about hardest and
that our own learning `019ed4db` already names: **the verification gate is opt-in and off by
default**, so the default loop path fabricates `checks_passed: true` — the live "Ralph Wiggum"
failure mode. Beyond that, a whole **cluster of gate/safety controls are off-by-default, inert, or
absent**: the **true-north metric** (cost-per-*accepted*-change, never computed), the **security
scan gate** (scanners exist but aren't enforced on the autonomous land path), **scope guardrails**
(the risk-tier infra never blocks), **runtime secret-scrubbing** (loop output isn't scrubbed for
keys/tokens), **lessons→loop feedback** (write-only on the campaign path), and a **readiness
preflight** + **gate-rot canary** (both absent). The pattern is consistent and verified: Powernode
scores **high on building blocks, low on gates** — exactly the article's thesis that the harness
and its verification gates, not agent cleverness, are the bottleneck (see the
[maturity scorecard](#loop-maturity-scorecard)).

| # | Framework idea | Powernode status | Gap |
|---|----------------|------------------|-----|
| Block 1 | Automations (cadence + goal-driven heartbeat) | Cadence **strong**; goal-driven **weak** | [G5](#g5) |
| Block 2 | Worktrees (isolated, auto-removed) | **Ahead** | — |
| Block 3 | Skills (write once, read every run) | **Ahead** (versioned/evolve/compose) | provenance [G6](#g6) |
| Block 4 | Connectors (MCP) | **Ahead** (~540+ tools) | tracker/error connectors [G8](#g8) |
| Block 5 | Sub-agents (maker/checker) | **Built** but off + not in loop | [G3](#g3) |
| MVL | Automation → Skill → State → Gate | 3 of 4 strong; **gate** weak | [G1](#g1) |
| State | Durable state files | **Ahead** (DB-backed) | — |
| State | Lessons fed back each iteration | **Write-only** on campaign path; promoted only at completion | [G12](#g12) |
| Failure | Ralph Wiggum (fabricated completion) | **Live by default** | [G1](#g1) |
| Failure | Goal drift (re-read base files each run) | **Mostly absent** (loaded once/session; decisions never re-injected) | [G12](#g12) |
| Failure | Agentic laziness | Partial (no separate completion judge) | [G3](#g3),[G5](#g5) |
| Failure | Comprehension debt / cognitive surrender | **Conditional** — safe under default `trusted`; autonomous/core-mode auto-approves | — |
| Failure | Gate rot (gates silently stop catching) | **Absent** | [G11](#g11) |
| Safety | Scope guardrails (never touch payments/auth/arch) | **Inert** (RiskContract never blocks; hooks CLI-only) | [G10](#g10) |
| Security | SAST + CVE + secret gate before merge | Tools exist, **not enforced in loop** | [G4](#g4) |
| Security | Credential leaks in logs | **Refuted** — runtime loop output unscrubbed for keys/tokens | [G15](#g15) |
| Security | 30-day token-scope audit | **Missing** | [G7](#g7) |
| Governance | Loop-readiness preflight (4-condition pre-run gate) | **Absent** | [G13](#g13) |
| Metric | Cost per **accepted** change (≥50% floor) | **Missing** (cost & lands never joined) | [G2](#g2) |

---

## Two runtimes — and why the cost dimension is runtime-specific

The framework's cost machinery (Condition 3, the dollar true-north metric, token/cost caps)
assumes a **metered** plan. Powernode runs loops on **two distinct runtimes**, split by *who
calls the LLM and who pays for tokens* — the `claude_code` vs `platform_*` driver routing
(`server/app/models/ai/ralph_loop.rb:18-22` `DRIVER_KINDS`;
`server/app/services/ai/dev_loop/campaign_driver.rb` `apply_driver_routing!` / `delegate`).

| | **Flat-rate CLI-executor loop** | **Metered platform-executor loop** |
|---|---|---|
| Driver kind | `claude_code` (see note) | `platform_agent` / `platform_team` / `platform_mission` |
| Who calls the LLM | An external agentic CLI drains the **dev-loop pull queue** (`dev_next_task`/`dev_complete_task`); the platform calls **no** LLM | The platform executor, on the account's provider keys |
| Examples | Claude Code, Grok CLI, OpenAI/Codex CLI, Gemini CLI — any MCP-capable agent CLI on a flat-rate plan | Platform-driven agents / teams / missions |
| Cost model | **Flat-rate** — marginal token cost ≈ 0 | **Metered** — real $ per token |
| Posture | **Aggressive**: more sub-agents, more verification passes, higher effort, parallel fan-out | **Frugal**: cost-aware, capped |
| Condition-3 (token budget) | Does **not** apply | Applies |
| True-north metric | **Acceptance rate** (anti-churn / human-review bandwidth) | **Cost per accepted change** (dollars) |
| Right hard-stops | Iteration limit + wall-clock timeout | + token/cost budget cap |

> **Note — the distinction is the *cost model*, not the vendor.** The pull-queue bridge
> (`dev_next_task`/`dev_complete_task`) is MCP-client-agnostic, so *any* flat-rate agent CLI
> (Claude Code, Grok, Codex, Gemini, …) is a flat-rate executor. The code currently labels this
> driver `claude_code`, a misnomer once non-Claude CLIs drive loops — see [G9](#g9).

**Therefore:** the verification gate ([G1](#g1)) applies to **both** runtimes and matters *more*
on aggressive flat-rate executor loops — when you take liberties with tokens, the gate is the
safety, not the budget. The *dollar* parts of [G2](#g2) and the token/cost caps in [G5](#g5) are
**metered-platform concerns**; flat-rate executor loops instead need an acceptance-rate floor and
iteration/wall-clock stops. (This runtime split refines the raw `configuration.gaps` titles on the
campaign — treat this doc as canonical.)

---

## The four conditions for a viable loop

| Condition | Powernode |
|-----------|-----------|
| **Task recurrence** (weekly+) | ✅ Campaigns exist precisely for open-ended, self-refilling work (`docs/contributing/conventions/autonomous-campaigns.md`). |
| **Automated verification** (objective gate) | ⚠️ The weak link — built but default-off ([G1](#g1)). |
| **Token-budget absorption** | **Runtime-specific** (see [Two runtimes](#two-runtimes--and-why-the-cost-dimension-is-runtime-specific)). Irrelevant for flat-rate CLI-executor loops; for metered `platform_*` loops cost/tokens are *recorded* per iteration (`iteration_execution.rb:173-177`) but **no hard cap** stops a loop on spend ([G5](#g5)). |
| **Agent senior tooling** (logs, repro env, runtime exec) | ✅ Container logs, sandboxed test execution, instances, docker exec — strong. |

---

## The five building blocks

### Block 1 — Automations ("the heartbeat")
- **Cadence loops — strong.** `Ai::RalphLoop` `scheduling_mode ∈ manual|scheduled|continuous|event_triggered|autonomous` (`server/app/models/ai/ralph_loop.rb:16`); cron / fixed-interval / duty-cycle via `schedule_config` (`server/app/models/concerns/ai/ralph_loop_concerns/scheduling.rb`). Harness `/loop` mirrors it.
- **Goal-driven loops — weak.** The only automatic terminator is "task queue drained" (`all_tasks_completed?`, `.../ralph_loop_concerns/task_and_learning.rb:18-22`). `completion_assessment` (`dev_loop_tool.rb:483-498`) evaluates `configuration.completion` criteria but is **report-only** — no explicit goal predicate, and **no separate model judges "done."** → [G5](#g5).

### Block 2 — Worktrees ("parallel without collision") — **ahead**
`scripts/prepare-worktree.sh` (isolated worktree + offline submodules + **per-worktree test DB** via `TEST_ENV_NUMBER`), models `Ai::Worktree` / `Ai::WorktreeSession`, git ops `server/app/services/ai/git/worktree_manager.rb`, branch-per-campaign (`campaign/<id>`), and auto-cleanup worker jobs (`ai_worktree_cleanup_job.rb`, `…_timeout_job.rb`). Exceeds the framework's baseline (isolated DB per tree).

### Block 3 — Skills ("write once, read every run") — **ahead, one gap**
`Ai::Skill` is versioned + DB-persisted (`server/app/models/ai/skill.rb`): `system_prompt` + `commands` + declarative `recipe` + attached KB/MCP servers. Create / evolve / **auto-evolve** / compose / mutate / health / attach all exist (`server/app/services/ai/skill_graph/*`, `…/self_improvement/skill_mutation_service.rb`, `…/missions/skill_composition_service.rb`). Real `SKILL.md` dirs exist in the harness (`.claude/skills/*/SKILL.md`).
- **Gap — provenance / injection audit.** No `provenance` / `trust_level` / `signature` column on `ai_skills`; `SkillService#create_skill|update_skill|assign_to_agent` persist/attach `system_prompt` verbatim with no content scan. `trust_tier_at_proposal` only auto-approves *internal* proposals (`ai/skill_proposal.rb:77`); community `verified` is a manual flag on **agents**, not skill content. → [G6](#g6).

### Block 4 — Connectors (MCP) — **ahead, minor gaps**
Genuinely MCP-native: full stack under `server/app/services/mcp/*`; **~540–561 tools** (`docs/reference/auto/mcp-tools.md`, `server/app/services/ai/tools/platform_api_tool_registry.rb`). External connectors: **Gitea** (16 tools), chat/notify (Slack/Discord/Mattermost/Telegram/WhatsApp adapters), databases/APIs (`data_source_*`, 29 tools, incl. `data_source_provenance`).
- **Gaps vs named set:** no **Linear/Jira** issue-tracker connector; no **Sentry/error-tracker** connector (GitHub → we are Gitea-native instead). → [G8](#g8).

### Block 5 — Sub-agents (maker/checker, Evaluator-Optimizer) — **built, but off + not in the loop**
The pattern exists in real code: `server/app/services/ai/reasoning/output_evaluator_service.rb` (separate, **independently-modeled** evaluator → `pass|revise|reject`), the revise loop in `agent_tool_bridge_service.rb:342-366`, reviewer-as-different-agent with an explicit **self-review ban** (`ai/team_authority_service.rb:187-200`), and per-agent model tiers (`ai/agent_model_selector.rb:38-46`).
- **Gap:** it is **opt-in (default off)** and, per the loop audit, **not wired into the Ralph/dev-loop/campaign completion path** — `Ai::Learning::LlmJudgeService` judges *knowledge* quality, not task completion. Maker-checker survives in the loop only as **advisory prompt text** ("don't trust green alone", `campaign_driver.rb:13-14`). → [G3](#g3).

---

## Minimum-viable-loop architecture (Automation → Skill → State → Gate)

| Part | Powernode | Status |
|------|-----------|--------|
| Scheduled automation | `Ai::RalphLoop` scheduling | ✅ |
| Targeted skill | `Ai::Skill` / harness `SKILL.md` | ✅ |
| Durable state file | `Ai::ProgressEntry` + `Ai::CampaignDecision` + `Ai::ParkedQuestion` (DB-backed; replace the old `~/.claude` markdown) | ✅ **ahead** |
| Automated **gate** | `Ai::Ralph::TestVerificationService` + sandbox `AiTestExecutionJob` | ⚠️ **opt-in / off** → [G1](#g1) |

State models (the framework's `last_run` / counters / `in_progress` / `lessons_learned`):
`progress_entry.rb` (snapshot counters + `per_loop_summary`/`improvement_metrics`),
`campaign_decision.rb` (typed decision log + rationale), `parked_question.rb`
(`open→answered`, reopens blocked tasks). DB-backed > flat JSON.

**Caveat ([G12](#g12)):** the `lessons_learned` half of the framework's state file is *write-only* on the
campaign path — per-iteration learnings land in a JSON column that `dev_next_task` never re-reads,
and they reach the embedded/searchable store only at **loop completion** (`state_machine.rb:59`),
which for a 500-iteration campaign effectively never fires mid-run. So the state *counters* are
ahead, but the *lessons feed back into the loop* is broken.

---

## Failure modes

### Ralph Wiggum (premature completion) — **live by default**
This is the central finding. The default loop path **fabricates** the verification flag:
- `server/app/services/ai/ralph/task_executor.rb:561` & `:189` — `checks_passed: true` hardcoded on any successful agent run.
- `server/app/services/ai/tools/dev_loop_tool.rb:300-306` — `record_outcome` takes pass/fail from the **agent's own** `outcome` param and sets `checks_passed: true`.
- The loop then trusts it: `iteration_execution.rb:183-189` → `task.pass!`.

The **real gate exists** — `Ai::Ralph::TestVerificationService` (its header literally calls itself "the replacement for the autonomous loop's fabricated `checks_passed: true`") runs the suite in a sandbox (`worker/app/jobs/ai_test_execution_job.rb`) and resolves the task from the real exit code (`internal/ai/ralph_loops_controller.rb:97-138`). **But** it only fires when `ralph_loop.real_test_execution?` is true, which requires `configuration["real_test_execution"]==true` **and** a `configuration["test_command"]` (`ralph_loop.rb:103-109`) — **off for every loop by default**, including all campaign and `/dev-loop` loops.

Our own learning **`019ed4db`** already records this verbatim: *"never from the loop's self-reported `checks_passed` (trusted verbatim, thus gameable)"* — mitigated so far only by the `RalphTask.improvement_scoreboard` revert-rate signal, **not** a real test gate. → [G1](#g1).

### Goal drift — **mostly absent** (corrected on re-verification)
The framework's mitigation is *re-reading base structural files every iteration*. Verified: on the **campaign path** the executor payload (`dev_loop_tool.rb:446-465`) carries only task details + branch/guardrails — it never re-injects CLAUDE.md/conventions or `Ai::CampaignDecision`s, and CLAUDE.md is loaded **once at CC session start**, not per `/dev-loop` iteration. (The platform-driven path re-injects `recent_learnings` via `iteration_execution.rb:121` but also not base files/decisions.) My earlier "partial — SessionStart digest" was too generous. → [G12](#g12).
### Agentic laziness — **partial.** No hard `/goal` predicate evaluated by a separate model. → [G3](#g3),[G5](#g5).
### Comprehension debt / cognitive surrender — **conditional** (corrected on re-verification)
*No batch-approve surface exists* (zero `*_approve_all`; every approval is single-id) and the land queue is serial (`landing_queue.rb:14` `MAX_ACTIVE_PER_TARGET = 1`), so auto-discovered changes **cannot** be bulk-waved-through — and under the **default `trusted`** authority each land stays `pending_approval` for one-at-a-time human review (`land/approval_binding.rb:45`). **But** the comprehension gate vanishes in three cases: `autonomous` authority auto-approves each land (`approval_binding.rb:82-88`), mission lands always auto-approve, core-mode (no governance extension) auto-proceeds (`approval_workflow_service.rb:35`), and the branch-protection merge is **self-approved by the land** (`land_service.rb:53-54`). So: holds by default, absent in the autonomous/core-mode path.

---

## The security tax (unattended loops are attack surfaces)

| Defense | Powernode | Status |
|---------|-----------|--------|
| Blocking SAST + dep-CVE + secret scan **before merge** | Scanners exist — gitleaks (optional local pre-commit, `scripts/install-git-hooks.sh`), Brakeman (**GitHub-only** `server/.github/workflows/ci.yml:24`), supply-chain CVE/SBOM/sign/policy-gate step handlers (`worker/app/services/devops/step_handlers/*`, prod copies in optional `extensions/supply-chain/`) — but **none run in the campaign land/merge path**. `Ai::Land::LandService` leans on "post-merge CI + auto-rollback" (`land_service.rb:12-13`), and the Gitea land workflows run **no** security scans. | ⚠️ **not enforced** → [G4](#g4) |
| Audit external skills | No skill content/provenance audit | ⚠️ → [G6](#g6) |
| Prevent credential leaks in logs | **Refuted at runtime** (on re-verification). `CLAUDE.md` crypto-safety stops the *human/CLI* emitting keys, but the autonomous loop's own output is unscrubbed: the runtime sanitizer (`data_management/sanitizer.rb:8-75`) matches only **PCI card data** (no API-key/token/secret/env regex), the global log formatter calls `sanitize_string` not `sanitize_hash` (`pci_compliance.rb:54`), agent/loop output is persisted **raw** (`iteration_execution.rb:162`, `campaign_driver.rb:218`), and the **worker that runs the loop has no sanitizer at all**. | ⚠️ **not scrubbed** → [G15](#g15) |
| Audit API-token scope every 30 days | Only expiry/reaper jobs (`worker/config/sidekiq.yml`); `ai_provider_credentials.access_scopes` stored but never reviewed for over-provisioning | ⚠️ **missing** → [G7](#g7) |

---

## True-north metric: Cost per **Accepted** Change (≥50% acceptance floor) — **missing**

The framework's single most important metric. Powernode tracks both halves but **never joins them**:
- **Cost** lives at the agent-execution grain (`ai_agent_executions.cost_usd`/`tokens_used`) and rolls into `Ai::RoiMetric` as `cost_per_task_usd` — but that divides by *completed* tasks, not *accepted* ones (`server/app/services/ai/analytics/cost_analysis_service/roi_analytics.rb:65`).
- **Acceptance** lives separately on `Ai::CampaignLand` (`landed | rejected | rolled_back`, `server/app/models/ai/campaign_land.rb`) — and that table has **no cost/token column**, so a human-approved merge is never tied to the spend that produced it.
- `Ai::Campaign` counters are `total/completed/failed/blocked_tasks` only — no cost, no accepted count, **no acceptance rate, no net-loss guard**.

→ [G2](#g2).

---

## The gaps (campaign scope)

Ordered by priority. Each is STAGE-only, test-first, individually approved.

<a id="g1"></a>**G1 — Make the real verification gate the default (kill Ralph Wiggum).** *[High]*
Stop hardcoding `checks_passed: true`; default `real_test_execution` **on** (or required) for campaign/`dev-loop` loops with framework auto-detection (`TestVerificationService` already detects rspec/pytest/jest/go/cargo), and fail-closed when no objective gate can run. This is the framework's #1 mitigation **and** our own flagged weakness (`019ed4db`).

<a id="g2"></a>**G2 — Acceptance-rate floor (both runtimes) + cost-per-accepted-change (metered loops).** *[High]*
Compute an **acceptance rate** from accepted `Ai::CampaignLand` records vs attempts and add a `stop_conditions.min_acceptance_pct` (default 50%) net-loss guard — this applies to **both**
runtimes (anti-churn). Separately, for **metered `platform_*` loops only**, join token/$ cost to
accepted lands and surface "cost per accepted change." For flat-rate CLI-executor loops the dollar
figure is not the optimisation target — acceptance rate is.

<a id="g3"></a>**G3 — Wire maker/checker into the loop.** *[Medium]*
Apply the existing `OutputEvaluatorService` / `review_workflow_service` (separate verifier model, self-review ban) to the Ralph/dev-loop task-completion path, not just general agent execution; add a first-class "cheap-explore / strong-verify" preset.

<a id="g4"></a>**G4 — Security gate on the autonomous land path.** *[Medium-High]*
Wire secret-scan (gitleaks) + SAST (Brakeman) + dep-CVE (supply-chain handlers, via a **generic seam** — core must not depend on the extension) as a **blocking** gate before campaign land/merge.

<a id="g5"></a>**G5 — Goal-driven completion + runtime-aware hard caps.** *[Medium]*
Promote `completion_assessment` from report-only to an actual goal terminator. Enforce **iteration
+ wall-clock timeout** stop-conditions on **both** runtimes. Enforce **token/cost** hard-caps on
**metered `platform_*` loops only** (currently recorded but never gating) — leave flat-rate
CLI-executor loops uncapped on tokens by design (be aggressive).

<a id="g6"></a>**G6 — Skill provenance / injection auditing.** *[Low-Medium]*
Add `provenance`/`trust_level` to `ai_skills` and an injection/content scan on create/update/attach, especially for any external/community import path. (Mirror the existing `data_source_provenance`.)

<a id="g7"></a>**G7 — Periodic token-scope / permission-creep audit.** *[Low]*
Scheduled job that reviews `access_scopes` on `ai_provider_credentials` (and API tokens) for over-provisioning on a 30-day cadence.

<a id="g8"></a>**G8 — Connector breadth.** *[Low]*
Add Linear/Jira issue-tracker and Sentry/error-tracker MCP connectors (the loop already has internal analogs via `report_issue`/`escalate`).

<a id="g9"></a>**G9 — Generalise the executor-driver taxonomy (vendor-neutral).** *[Low]*
The flat-rate executor driver is hardcoded as `claude_code` (`server/app/models/ai/ralph_loop.rb:21` `DRIVER_KINDS`, `claude_code_driven?` at `:90`), but the dev-loop pull-queue is MCP-client-agnostic — Grok CLI, OpenAI/Codex CLI, Gemini CLI, etc. are equally valid flat-rate executors. Generalise to an `external_cli` / `flat_rate_executor` concept (with `claude_code` as a labelled instance) so non-Claude CLIs are first-class and per-vendor attribution/telemetry is possible. The mechanism already works; this is naming + telemetry, not unblocking.

### Added after adversarial re-verification (round 2)

The following were either under-weighted in round 1 or are corrections to claims I had marked
"covered." All are code-verified.

<a id="g10"></a>**G10 — Enforce loop scope guardrails (never touch payments/auth/crypto/architecture).** *[Medium-High]*
The article's "Never touch `src/payments/`,`src/billing/`" control has **no enforced equivalent**. The
infra half-exists but is **inert**: `Ai::CodeFactory::RiskContract` tiers files (`low…critical`) but
`PreflightGateService#evaluate` returns `passed: true` for *every* tier including `critical`
(`preflight_gate_service.rb:52-60`); the loop-side hooks `code_factory_preflight_check` /
`code_factory_evidence_satisfied?` (`ralph/execution_service.rb:28-62`) have **zero callers**;
campaign "guardrails" are **prompt text** only (`campaign_driver.rb:10-16` → `dev_loop_tool.rb:459`);
and `core-purity`/crypto checks run only as **edit-time CLI hooks** that don't fire on the
platform-executed path. **Reuse-first fix:** wire the already-built RiskContract/preflight to actually
*block* denylisted paths and `critical`-tier changes on the autonomous path (don't build new).

<a id="g11"></a>**G11 — Gate-integrity canary ("gates rot over time").** *[Medium]*
No mutation testing / deliberate failure-injection exists (`mutant`/`stryker`/`mutmut` absent;
"canary" is deploy-only; "chaos" is an unused enum value). Add a periodic check that injects a
known-bad change to confirm the verification gate still fails closed — otherwise a silently-broken
gate ([G1](#g1)) reads as green forever.

<a id="g12"></a>**G12 — Close the lessons→loop feedback (and re-inject base context each iteration).** *[High]*
On the campaign path, per-iteration learnings are **write-only** to a JSON column `dev_next_task`
never re-reads, and reach the embedded/searchable store only at loop completion
(`state_machine.rb:59`) — so a long campaign never learns from itself mid-run. Also neither path
re-injects `Ai::CampaignDecision`s or CLAUDE.md/conventions per iteration (the goal-drift mitigation).
Fix: re-inject recent learnings + open decisions + base structural files into each iteration's
payload (`dev_loop_tool.rb:446-465`), and promote learnings to the compound/embedded store mid-run,
not only at completion. (This is the code-level root of the "stalled knowledge-feedback pipeline".)

<a id="g13"></a>**G13 — Loop-readiness preflight (operationalise the 4 conditions as a pre-run gate).** *[Medium]*
Loop/campaign start does **no** readiness validation — `loop_lifecycle.rb:11-12` checks only
status + non-empty queue; the CodeFactory "preflight" is PR-risk and runs *after* execution. Add a
true pre-run gate that refuses/warns when the target has no automated gate, no runnable env, or
[G1](#g1) verification is off. See [Operating doctrine](#operating-doctrine--the-conditions-as-an-enforced-gate).

<a id="g14"></a>**G14 — Codify the good-first-loop allowlist / keep-manual denylist as policy.** *[Low]*
The article is prescriptive: loop on CI-triage / dependency bumps / lint-fix; keep auth, crypto,
payments, architecture, and subjective "done" **manual**. Codify this as a policy catalog that feeds
G10's enforcement and G13's preflight, rather than leaving it to prompt text.

<a id="g15"></a>**G15 — Runtime credential/secret scrubbing of loop & agent output.** *[Medium-High]*
Correction to a "covered" claim. Extend `DataManagement::Sanitizer` with API-key/bearer-token/secret/env
patterns (today it's PCI-card-only), make the log formatter scrub structured output (`sanitize_hash`,
not just `sanitize_string`), sanitize agent/loop output before it's persisted
(`iteration_execution.rb:162`, `campaign_driver.rb:218`), and add a worker-side log formatter (the
worker that runs the loop currently has none).

---

## Operating doctrine — the conditions as an enforced gate

*(Framing chosen in addition to the engineering gaps: treat the article as operating policy, not just a feature checklist.)*

The 4 conditions + 30-second checklist are only worth anything if a loop **cannot start** without
them. Today nothing enforces them at start ([G13](#g13)). Adopt them as a governance **preflight**
every campaign/loop must pass before it activates — fail → `park_question!`, don't run:

1. **Objective gate present** — an automated test/lint/build is discoverable for the target, and
   real verification is enabled ([G1](#g1)). No gate → no loop.
2. **Hard-stops set** — iteration + wall-clock for every loop; token/cost cap for *metered* loops
   ([G5](#g5)); flat-rate CLI loops stay token-uncapped by design.
3. **Scope in bounds** — target is on the good-first allowlist and clear of the keep-manual denylist
   ([G10](#g10),[G14](#g14)).
4. **Runnable env** — the executor can run and observe the code (logs, repro).
5. **Approval posture explicit** — for non-`autonomous` authority a human land-gate precedes merge;
   for `autonomous`, [G15](#g15) scrubbing + [G4](#g4) security gate are mandatory compensating controls.

This converts the article from a checklist we *read* into a gate the platform *enforces* — and it's
the natural home for [G13](#g13).

---

## Loop maturity scorecard

*(Second chosen framing: a rubric to track over time, not a one-shot comparison.)*
Score per dimension: **0** absent · **1** built-but-off / inert · **2** partial / conditional ·
**3** enforced by default. Current state (2026-06-29):

| Dimension | Score | Note |
|-----------|:---:|------|
| Worktrees | 3 | isolated + auto-cleanup + per-tree test DB |
| Connectors (MCP) | 3 | ~540+ tools, real external connectors; **G8** added an outbound issue/error-tracker seam (`TrackerRegistry` + Linear/Jira/Sentry adapter scaffolding; full vendor API clients = follow-up) |
| Durable state (counters) | 3 | DB-backed ProgressEntry/Decision/ParkedQuestion |
| Automations (cadence+goal) | 3 | **G5 closed** — `completion_assessment` is now a real `goal_met` terminator (cadence already strong) |
| Skills | 3 | **G6 closed** — provenance + trust_level on ai_skills; injection/content scan on create/update gates external content; untrusted skills blocked on attach |
| Comprehension/approval | 2 | conditional — default-safe, autonomous auto-approves |
| Hard-stops | 3 | **G5 closed** — iteration + wall-clock (both runtimes) + metered token/cost caps enforced via shared `halt_reason`/`runtime_cap_reason`; flat-rate stays token-uncapped by design |
| Sub-agents (maker/checker in loop) | 2 | **G3 (wired)** — OutputEvaluatorService now composes into the loop completion path (opt-in `maker_checker` + cheap-explore/strong-verify preset, self-review ban) |
| Verification gate (Ralph Wiggum) | 3 | **G1 closed** — real gate now default-on (opt-out), fail-closed, worker auto-detects framework |
| Lessons→loop feedback | 3 | **G12 closed** — recent learnings re-injected per iteration + each learning embedded mid-run (not only at completion) |
| Goal-drift mitigation | 2 | **G12 (partial)** — open decisions + base-context files re-injected into each dev_next_task payload; per-iteration base-file *contents* still a follow-up |
| Security scan gate | 2 | **G4 (partial)** — blocking core gate on the land path (secret-scan enforced; SAST/CVE via `SecurityScannerRegistry` seam) parks autonomous lands on findings; worker-side full-diff scanners = follow-up |
| Runtime secret-scrubbing | 2 | **G15 (partial)** — loop output scrubbed (PCI + secrets) at server persistence; worker-side + global log formatter still raw |
| Scope guardrails | 2 | **G10 (partial)** — denylist + RiskContract critical-tier now BLOCK on the dev-loop completion path (PreflightGate critical-block fixed); platform/land-path enforcement is follow-up |
| Gate-integrity canary | 3 | **G11 closed** — daily `GateCanaryService` feeds known-good/bad through the G1 gate and alerts if it stops failing closed |
| Readiness preflight | 3 | **G13 closed** — pre-run gate blocks a loop with no objective gate; surfaces caps/env warnings |
| True-north metric | 2 | **G2 closed** — acceptance rate computed + floor enforced by default (both runtimes); cost-per-accepted surfaced (metered only). Report-only on the $ side keeps it at 2, not 3 |

**Read of the scorecard (original 2026-06-29):** building blocks averaged **~2.6/3**; gates/safety
averaged **~0.7/3**. That spread *was* the finding — Powernode had the richest substrate and the
weakest gates, precisely the failure mode the article warns about ("harness engineering > agent
cleverness"). The campaign's job was to raise the bottom of this table.

**Read after the campaign drain (2026-06-30):** all 15 gaps closed (see the Progress note under [Driving the gaps](#driving-the-gaps)).
Gates/safety now average **~2.4/3** (from ~0.7) — verification gate, hard-stops, lessons-feedback,
gate-canary, and readiness-preflight are at 3; security-gate, secret-scrubbing, scope-guardrails,
goal-drift, and true-north are at 2 with the remaining work being cross-service depth (worker-side
scanners, platform/land-path enforcement, cost-side gating) rather than missing foundations. The
substrate↔gates spread that *was* the finding is largely closed.

**Progress (2026-06-30):** **ALL 15 gaps closed** on the campaign branch (STAGE-only, not pushed),
one commit per gap, each test-first with its own specs:

| Gap | Commit | Gap | Commit |
|---|---|---|---|
| G1 | `18abb8bf` | G9 | `56ba57aa` |
| G2 | `13cdd0ce` | G10 | `ff740702` |
| G3 | `a4cc245b` | G11 | `77d522bb` |
| G4 | `2ea67b90` | G12 | `47470e01` |
| G5 | `fb942d26` | G13 | `c1b8af6a` |
| G6 | `6d4bfeb8` | G14 | `741c9c69` |
| G7 | `2dfa2594` | G15 | `6cf50f91` |
| G8 | `8b72f77a` | | |

**Open follow-ups (noted in commit bodies, not blockers):** worker-side full-diff SAST/CVE + deep
secret-scan registering into G4's `SecurityScannerRegistry`; G10/G15 enforcement on the platform/land
path (not just the dev-loop completion path) + the global log formatter; full vendor REST/auth clients
behind G8's tracker adapters; feeding a real unified diff into G3's checker.

**Increment ledger entries still pending** — platform MCP was disconnected for the implementing
session, and a premature-finalization hazard (`completion_pct:100` stop on a 0-seeded-task loop) would
auto-finalize the live campaign on the first recorded increment; record via MCP once reconnected, after
seeding/fixing the campaign. A pre-existing `task_executor_spec` failure set (AI-provider/webmock,
unrelated to this campaign) is flagged separately.

---

## Driving the gaps

These gaps are tracked by the **Loop Engineering Parity** campaign
(`platform.campaign_*`, decision authority `trusted`, STAGE-only). It drains **G1→G15** in priority
order, one improvement per `run`, each individually approved. (The on-platform `configuration.gaps`
enumerates the round-1 subset G1–G8; **this doc is canonical** and supersedes it with G9–G15.)

Two leverage clusters:
- **Make the loop trustworthy** — [G1](#g1) (real gate) + [G2](#g2) (acceptance/cost-per-accepted):
  converts the loop from "trusts a fabricated flag, optimises throughput" to "gated on a real test
  run, optimises the right metric per runtime."
- **Make it safe to walk away from** — [G10](#g10) (scope guardrails) + [G12](#g12) (lessons +
  base-context feedback) + [G15](#g15) (secret-scrubbing) + [G13](#g13) (readiness preflight):
  the controls that matter most precisely because flat-rate CLI loops are meant to run aggressively
  and unattended. Per the [scorecard](#loop-maturity-scorecard), this is the cluster scoring lowest.
