# Vision-alignment audit — 2026-09-10

**Scope.** The four weeks of committed work from 2026-08-13 to 2026-09-10 across core
(`/`), the system extension (`extensions/system`) and one private extension,
evaluated against the platform's stated vision on four questions: (1) is the work on the
right track for the vision, (2) is AI/MCP integration thorough and comprehensive, (3) do the
agent skills, prompts and guardrails support autonomous platform development,
implementation and management, and (4) are self-introspection, self-diagnosis and
prescriptive remedies perpetually present and active.

**Method.** Five parallel read-only sweeps (commit digest; vision claims extracted from docs;
MCP surface vs REST surface; agent seeds, prompts, guardrails and executor paths; every
scheduled loop and its terminal actuator), plus live reads of the production control plane
over MCP at 17:30 UTC today (health, signals, improvements, campaigns, dev-improve queue,
learnings, sensor config). Every claim below cites a file and line or a live read. Nothing was
implemented; this is a report (`guidance-audit-report-only`).

**Prior audits this one re-scores:** the nine last-mile dead wires of
[platform-vision-gap-discovery-2026-08-06](platform-vision-gap-discovery-2026-08-06.md),
the act/sense/create arms of
[autonomous-infrastructure-readiness-2026-08-12](autonomous-infrastructure-readiness-2026-08-12.md),
and gaps G1–G10 of
[autonomous-project-platform-gap-map-2026-09-05](../reference/autonomous-project-platform-gap-map-2026-09-05.md).

---

## 1. Verdict

**On the right track, and measurably further along than four weeks ago — but the platform
still cannot improve itself without a human session driving, and the two subsystems built to
judge its own quality feed nothing.**

| Question | Verdict | One-line reason |
|---|---|---|
| 1. On track for the vision | **Yes, with one structural caveat** | 6 of 9 dead wires from 08-06 are fixed, all 10 gap-map items were built or deliberately deferred, and the environment/plane model landed. The caveat: the vision says *agents implement*; server-side, the implementing agent cannot write a file. |
| 2. MCP thorough and comprehensive | **Comprehensive on infrastructure; not a control plane for the platform itself** | 634 actions; fleet, network, storage, code, knowledge and the autonomy loop are fully reachable. Identity, roles, audit log, schedules, LLM providers, webhooks and the whole of one private extension are unreachable. 90% of actions carry no safety annotation although the ground truth exists for all 634. |
| 3. Skills/prompts support autonomous dev/impl/mgmt | **Management yes; development and implementation only via Claude Code** | Guardrails are genuinely code-prepended to every executor. Fleet agents have real actuators. The Platform Developer canonical has no file-write, shell or commit verb, and none exists in the registry to grant. |
| 4. Introspection perpetual, remedies present and active | **Sensing: yes, every minute. Remedy: partial. Self-judgement: built, never wired.** | ~95 cron entries, six per-minute ticks, 17 fleet appliers. Improvement discovery has no scheduled driver and the discovery verb is a prompt, not an analyzer. Self-challenge, LLM judge and skill evolution all terminate in rows nothing reads. |

The recurring failure shape, unchanged since August, is what the memory index calls
*exists, passes review, never executed*: a capability is built, seeded, scheduled and
documented, and its last hop is a flag nobody enabled, a row nobody reads, or a method that
does not exist. The four weeks fixed many instances of it in the fleet lane and introduced a
few new ones in the skill lane.

---

## 2. What the four weeks built

| Repo | Commits | fix | feat | refactor | docs | chore | merge |
|---|---:|---:|---:|---:|---:|---:|---:|
| core | 895 | 273 | 107 | 13 | 138 | 270 | 40 |
| system extension | 1132 | 456 | 175 | 78 | 182 | 7 | 99 |
| a private extension | 42 | 32 | 1 | 0 | 2 | 1 | 0 |

Core's `chore` mass is 225 submodule-pointer bumps. Excluding those and merges, the corrected
IMP-tracked : campaign-marked : ad-hoc ratio is roughly **4 : 1 : 3** in core and
**12 : 1 : 5** in the extension — most engineering flowed through the improvement queue,
which is the intended shape. 669 distinct IMP ids were closed; the dev-improve loop holds
845 passed, 22 pending, 1 blocked, 0 failed (live read).

Themes by weight, with the assessment the commit subjects support:

| Theme | Commits | Reading |
|---|---:|---|
| Fleet provisioning + instance lifecycle | 298 | new surfaces plus the worst fix:feat ratio (114:40) — correctness churn |
| SDWAN / ingress / network fabric | 197 | hardening of a built-out subsystem |
| Loop machinery (dev-loop, dev-improve, campaigns) | 174 | process infrastructure; 90 are merges |
| Module build / promote / release | 173 | new capability plus repeated integrity fixes |
| Governance, approvals, gated actions | 122 | new `gate_create!`/`gate_update!` seam, retrofitted across call sites |
| Agent hierarchy + canonical seeds (HIER-*) | 102 (+50 guardrail commits) | substantial new capability |
| MCP tool surface and catalog | 100 | `describe_tool` + one-line `tools/list` are new; ~70 are catalog regenerations |
| Fleet sensors and drift | 97 | **correctness rescue** — sensors that reported without measuring |
| Security / authz / PKI | 88 | hardening; a distinct mTLS burst 08-22..08-27 |
| Frontend primitives + sysfe drain | 73 | mass migration onto shared primitives |
| Autonomous Project Platform (APO) | 33 | one four-day burst, 09-02..09-05 |
| Environment / plane model | 17 | newest capability, 09-06..09-09 |
| Self-challenge | **0** | no commit touched it in four weeks |

Two shapes worth naming. First, the fleet-sensor theme reads, commit by commit, as a
self-diagnosis subsystem that was structurally present but not wired
(`23dfb636` wire drift_check to a real detector; `3ce4ab87` repoint a dead apply probe;
`0e40b232` correct 12 fabricated sensor signal kinds; `bd7d79f3` make the honeypot drill
able to fail). Second, learning-extraction commits were retirements and secret-scrubs, not
expansions; no commit subject named `BASE_GUARDRAILS` or `.claude/skills`.

### 2.1 Prior gaps closed

**The nine last-mile dead wires (08-06):** 6 fixed, 1 fixed-but-gated-off, 2 still dead.

| # | Lane | Status at HEAD |
|---|---|---|
| 1 | Core OODA closure had zero callers | **Wired, gated OFF** — `AiClosureDriverJob` every 15 min → `closure_driver_service.rb:49`; reads SiteSetting `ai.autonomy.closure_driver_enabled` which no seed or migration creates |
| 2 | Module promotion had no applier | **Fixed** — `decision_engine.rb:2004`, `:2404` |
| 3 | Adaptation plan never stamped | **Fixed** — `adaptation_dispatch_service.rb`, outcomes minted both ways |
| 4 | Adaptation approval cascade no-op | **Fixed** — target is now `Ai::DeferredOperation#on_approval_decision` (`deferred_operation.rb:120-132`) |
| 5 | Learning effectiveness poisoned the corpus | **Fixed** — `dev_loop_tool.rb:755`, `:1225-1239`; Laplace smoothing `compound_learning.rb:111-116` |
| 6 | `SkillMutationService` queried nonexistent columns | **Fixed** — `skill_mutation_service.rb:31` |
| 7 | `prompt_refinement` false actuator | **Fixed** — `improvement_recommender.rb:46-47`, `:135` |
| 8 | Skill A/B counters never written | **Still dead, and worse** — see §6.3 |
| 9 | Goal advancement only abandons | **Still dead at default settings** — reachable only through item 1's gated driver |

**Gap map G1–G10 (09-05):** all ten were built or explicitly deferred inside the Autonomous
Project Platform campaign (25 of 30 increments passed, three of which were reports rather than
code). Composite health, standing-signal hygiene, one scheduled agent duty, `Ai::Project`,
per-project team template, one front door, the no-bare-fact lint and SLO targets are on the
branch and deployed as of 2026-09-09. G6 (workload sense) was deliberately not built because a
precondition check found the gap elsewhere; G10 (sensor configurability) is partially closed —
5 of 37 sensors are MCP-tunable (see §6.2).

**Readiness doc's three arms (08-12):** the **act** arm now exists (adaptation dispatch); the
**sense** arm is still infrastructure-only ("deployed app code and containers remain unsensed",
`extensions/system/docs/FLEET_SENSORS.md:9`); the **create** arm has manifest authoring but no
build-payload path.

---

## 3. Vision alignment, claim by claim

The docs make 63 testable claims (extracted to the scratch notes of this audit; the load-bearing
ones are scored here). The framing both prior audits converged on still holds: *the verbs
exist; what is missing is the nouns and the clock.* Four weeks later the nouns are largely
there (Environment, Project, canonical teams, plane-scoped blast radius). The clock is the
remaining gap.

| Claim (cite) | Status | Evidence |
|---|---|---|
| Chat to provision end to end (`README.md:3`) | **Holds** | Two full autonomous-provisioning passes recorded as learnings (dryrun 2026-08-09), deterministic plan synthesis as keystone |
| A control loop keeps monitoring afterward (`README.md:5`) | **Holds for infrastructure, not for the workload** | `FLEET_SENSORS.md:9`: all but two sensors read infrastructure |
| 37 sensors on the live tick (`FLEET_SENSORS.md:5-7`) | **Holds** | Registry `fleet_autonomy_service.rb:276-463`; directory-vs-registry diff empty; live signals at 17:31 UTC today show `fleet.tick_started` and 18 signal kinds |
| Every autonomous action gated (`agents-and-autonomy.md:559`) | **Holds** | `AutonomyGate` at the `BaseTool` chokepoint (`fcb205f24`); environment gate (`783b00fe2`); fail-closed on unresolvable environment (`fleet_autonomy_service.rb:603-605`) |
| Control plane refuses to remediate itself (readiness §4) | **Holds with a live exception** | Pending offer: `BootImageDriftSensor` re-emits drift for the self-hosting node every tick, minting a standing approval INV-1 forbids (fingerprint `inv1_steady_state\|boot_image_drift_sensor.rb\|self_hosting_node`) |
| Platform Developer drains dev-improve continuously with nobody at a terminal (`platform-engineering-agents.md:140-161`) | **Does not hold server-side** | §5.3: no file-write, shell or commit verb in its families; `task_executor.rb:131-132` early-returns a tool-enabled agent before git tools attach; `git_tool_executor.rb:31-33` needs a `mission.repository` no campaign loop has |
| Platform Architect runs a closed governance loop (`platform-engineering-agents.md:232-294`) | **Holds — the one unattended offer producer** | `governance_gap_propose_executor.rb:194` files offers off the per-minute tick; nothing drains them without a session |
| Every operator decision feeds compound learnings (`extensions/system/README.md:76-77`) | **Partial** | `LearningExtractor.record_tick!` runs every tick but the rows it writes are shallow ("Fleet X → gate Y"); operator attribution feedback is the only decision-shaped learning |
| Skills evolve with A/B testing and self-learning (`knowledge-and-memory.md:523-547`) | **Does not hold** | §6.3 — versions written and activated, never served |
| Self-healing monitor triggers restart/failover/cleanup (`agents-and-autonomy.md:1049-1058`) | **1 of 4 arms live** | `self_healing_controller.rb:53-59` fails orphaned executions; the other three log only; `RemediationDispatcher` behind an unenabled flag |
| Weekly policy tuning proposes adjustments (`agents-and-autonomy.md:606`) | **Holds as a recommendation** | `autonomy_controller.rb:210-218`; no policy row is ever written from it |
| Campaigns never stall (`autonomous-campaigns.md:54-60`) | **Does not hold live** | Live: 8 active campaigns, 6 with zero tasks and no driver lease since 2026-09-08 |
| Release verbs approval-gated at every tier (`platform-engineering-agents.md:58-60`) | **Holds** | Prompt at `ai_engineering_agents_seed.rb:358-361`; gate rows |

**Documentation contradictions the docs themselves still carry** (15 found; the four that
mislead an agent): `README.md:20` inlines "571 actions across 63 tool classes" against
`mcp-and-tools.md:246` which forbids inlining counts (the catalog says 634/71 today);
`extensions/system/README.md:289-291` still says "expanded to 21" sensors beside `:59` saying
37; `agents-and-autonomy.md:1151` and `use-powernode-from-claude.md:105` name a systemd unit
form `CLAUDE.md` says is installed nowhere; and `extensions/system/README.md:12` calls the
layer "self-improving" while §6 below shows the improvement half is open.

---

## 4. MCP integration

**Comprehensive where it was pointed; absent where it was not.** 634 actions across 71 tool
classes, generated from one registry (`platform_api_tool_registry.rb:836`), with zero measured
drift between the registry, the four in-process advertisement surfaces and the 32 Claude Code
skeletons (381 agent-visible actions are a strict subset of 634;
`advertisement_surface_parity_spec.rb` asserts both arms with `contain_exactly`). The
one-line `tools/list` plus `platform.describe_tool` (`c06f7cb94`) is the right shape for a
600-verb catalog. Descriptions on mature verbs (`mutate_skill`, `system_cordon_instance`,
`system_promote_module_version`, `dev_next_task`) state preconditions, gate behaviour and the
next call — they are among the best tool descriptions in the field.

### 4.1 Gaps

| Gap | Size | Evidence |
|---|---|---|
| **Safety annotations not exported** | 569 of 634 carry none; `destructiveHint` appears nowhere in the codebase; 3 declared-mutating verbs advertise `readOnlyHint: true` | `tool_catalog.rb:61-66`, `:260-263` keys on a name-prefix heuristic while `declare_action(mutating:)` holds ground truth for all 634; `coordination_tool.rb:72-75` (`measure_pressure`, `perceive_pressure`, `perceive_signals`) |
| **Platform is not self-administrable over MCP** | users, roles, permissions, invitations, accounts/settings, audit logs, webhooks, schedules/cron, API keys, LLM providers and model catalog: **zero** MCP verbs | `server/config/routes.rb:892-1249` REST families with no tool; `ai/providers_controller` uncovered — the `system_*_provider*` family is cloud providers |
| **No general approval verb** | an agent cannot raise an `Ai::ApprovalRequest` or respond to one raised elsewhere | only `approve_deferred_operation` / `reject_deferred_operation` on the deferred-op workflow (`agent_autonomy_tool.rb:329-338`) |
| **Three extensions have zero tools** | marketing, supply-chain and one private extension (628 route lines) | no `ai/tools` directory exists in any of the three |
| **Core hardcodes 263 extension entries** | 41% of the registry violates extension isolation; acknowledged in-code | `platform_api_tool_registry.rb:802-810`; the `register_extension_tools` seam has one consumer and it is not the system extension |
| **Docs catalog over-states availability** | generated from unfiltered `.all_tools`, so it lists verbs the parity spec proves are dropped in core mode | `mcp_tool_catalog.rake:26` |
| **Thin descriptions on destructive verbs** | 194 under 80 chars; `delete_skill` (30), `toggle_skill` (29), `system_cancel_task` (21), `docker_restart_container` (19) | catalog statistics |

### 4.2 Self-diagnosis read verbs that lie

Of 25 read-side diagnosis verbs traced to their terminal data source, 19 read real data. Six
do not:

| Verb | Defect | Cite |
|---|---|---|
| `integration_health` | permanently `{unknown: N}`: the column it buckets has one writer with zero call sites | `integration_health_tool.rb:48,61-64`; `integration_instance.rb:162-168`; the sweep writes a jsonb blob the params permit, not the columns the verb reads |
| `system_platform_resilience` `failover_check` | three `rescue StandardError; []` then "No platform stress detected" — an exception reads as all-clear | `platform_resilience_executor.rb:442-469`, `:427` |
| `code_dead_code`, `code_find_duplicates` | fixed `{success: true, status: "enqueued"}` regardless of whether the worker is up | `code_analysis_tool.rb:208-214`, `:240-246` |
| `system_attribute_failure` | magic weights; a single candidate always yields `confidence: 1.0` | `attribute_failure_executor.rb:76`, `:132`, `:204` |
| `code_static_analysis` | headline `errors: 0` discards the `no_gemfile \| no_output` status | `static_analysis_service.rb:50-61`, `:98-104` |
| `learning_metrics` | `effectiveness_factor = avg \|\| 0.5` — an unmeasured input reports mid-range | `compound_learning_service.rb:656` |

`get_system_health` is honest but misnamed: it is AI-subsystem activity only. The real probe is
`system_platform_maintenance` with `op: "health_check"`, which is the strongest of the set
(13 subsystems, `not_measured` discipline, persisted snapshot).

---

## 5. Agents, skills, prompts, guardrails

### 5.1 What holds

- **`BASE_GUARDRAILS` is code-enforced and model-agnostic.** Prepended at `agent.rb:304` on
  every seam: MCP executor, LLM proxy, execution contexts, concierge, coordinator, skill
  executors, and verbatim into the Claude Code skeletons. `BootstrapVerbs::ACTIONS` is unioned
  onto every family-scoped agent so it can obey them, and a spec derives that set from the
  guardrail text (`bootstrap_verbs_spec.rb:71-72`) — a well-made ratchet.
- **Loop guardrails reach non-Claude executors.** `dev_next_task` re-derives HEAD + TAIL at
  pull time (`loop_guardrails.rb:49-51`), naming the production connector for `guidance-*`
  recall and the verification gate with the evidence-declaration contract.
- **32 canonical agents, 117 platform skills, 3 canonical teams**, all seeded, one skeleton per
  canonical (1:1 verified), delegation policies tight (Platform Developer may delegate only to
  the judge's type; Release Manager to nobody).
- **Trust really gates.** Capability matrix, execution gate, intervention-policy
  `trust_tier_minimum`, delegation authority, routing weight and kill-switch scope all read
  `Ai::AgentTrustScore`; it is written after every execution and decayed daily.
- **The Fleet Autonomy prompt** is the only one in the roster with a genuine
  sense→decide→gate→act→learn loop and five operating principles that are real remediation
  discipline (`fleet_autonomy_agent.rb:26-58`). The Release Manager prompt encodes four
  incident-derived rules from the memory index (verify by digest, ladder ≠ pointer, promote
  skew, self-hosted cannot recover itself).

### 5.2 Prompt criteria, Engineering hierarchy

(a) query knowledge first · (b) record learnings after · (c) verify by execution ·
(d) stop/escalation/approval boundaries · (e) self-diagnose before acting · (f) prescribe a
remedy on a gap.

| Agent | a | b | c | d | e | f |
|---|---|---|---|---|---|---|
| platform-architect | yes | yes | no (designs only) | **yes, exemplary** | partial (reuse-shaped, not health-shaped) | yes |
| platform-developer | yes | yes | **in text, not in capability** | yes | yes | yes |
| release-manager | partial | partial | yes | yes | **yes, strongest core** | partial |
| documentation-specialist | partial | yes | n/a | weak | yes | partial |
| llm-judge | no | no | no | no | no | no |
| fleet-autonomy | no | yes | yes | yes | **yes, strongest overall** | yes |

Gaps: `BASE_GUARDRAILS` carries no verification-gate line, so the 30 canonicals that never enter
the dev loop are never told to verify by execution. Platform Architect holds `skill_health`,
`skill_metrics` and `discover_improvements` in its families but its prompt never orders a
health read before designing. Release Manager and Documentation Specialist hand off rather
than open an improvement.

### 5.3 The Platform Developer cannot implement server-side

Three independent structural facts, each alone sufficient (`agent-prompts` sweep §7):

1. `task_executor.rb:131-132` — a tool-enabled agent early-returns into the tool bridge before
   the git executor attaches; Platform Developer is tool-enabled by definition.
2. `git_tool_executor.rb:31-33` — the only file-mutating path needs `ralph_loop.mission.repository`;
   `create_campaign_loop` (`campaign_driver.rb:449-470`) and the dev-improve singleton set neither.
3. `ai_engineering_agents_seed.rb:233-242` — no file/shell/commit verb in its families, and
   `grep bash|shell_exec|run_command|write_file|edit_file` over the registry returns nothing.

Consequence: `campaign_delegate` with no agent named produces a real, minute-ticking,
budget-consuming loop that recalls guidance, reads the code graph, reasons, and then reports
`dev_complete_task` with attested evidence and no diff. The evidence adjudicator
(`dev_loop_tool.rb:640-660`) correctly refuses to auto-close the linked offer on attested
evidence, so the damage is bounded to cost and a misleading record. The worker's real test
runner (`ai_test_execution_job.rb`) fires only on a `commit_sha` this path cannot produce.
There is no Claude-Code-in-a-container anywhere in the tree.

### 5.4 Other defects found

- **LLM judge is unreachable.** `EvaluationService#evaluate_execution` has zero production
  callers (spec only) and sits behind `:agent_evaluation`, registered off. Its parser reads a
  flat object (`llm_judge_service.rb:127-158`) while the seeded agent prompt orders a nested one
  with weights — never noticed because nothing calls it. The team seat "independent review of
  every drained task" (`ai_canonical_teams_seed.rb:69`) is enforced by no code.
- **Model-name governance has no enforcement.** ~24 genuine hardcoded model ids, 12 as
  `|| "model-id"` fallbacks in service logic (worst: `ai_response_job_concern.rb:91` falls to
  `gpt-4`; `agent_management_tool.rb:316` stamps a retired id as a pin;
  `devops_integration.rb:11` decides Claude-Code-capability by one id). `pattern-validation.sh`
  has 38 checks and none touch model names; `spec/lint/` has 10 ratchets and none for this.
- **HIER-P0:** nine leaves under `powernode-assistant` carry an empty `allowed_delegate_types`,
  which reads as unrestricted (`ai_agent_hierarchy_seed.rb:90-95`).
- `discover_skills` calls the raising `EmbeddingService#generate` so its keyword fallback is dead
  exactly when the embedding worker is down (`traversal_service.rb:38`).
- Claude Code self-reports via `record_agent_execution` write no skill usage, so one of the two
  sanctioned dev-improve drivers is invisible to `skill_health`.

---

## 6. Self-introspection and prescriptive remedies

### 6.1 Present and active — the sensing half

~95 cron entries (82 core, 12 system extension, 4 in a private extension), six firing every minute:
`SystemFleetReconcileJob`, `SystemCveResponderReconcileJob`, `AiRalphLoopSchedulerJob`,
`AiCampaignLandSchedulerJob`, `SystemFulfillmentRequestReconcileJob`, and the campaign-land
CI poll. Live confirmation at 17:31–17:33 UTC today: 100 fleet events in two minutes across 18
kinds, three `fleet.tick_started/complete` pairs, two CVE responder ticks, four skill
executions (`drift_remediate` ×2, `boot_image_drift_rollout`, `replace_instance`), 42
`system.config_drift`, 6 `decision.awaiting_operator` (all `remediation_stuck` on
`system.module_assign`), 3 `decision.pending` (`require_approval`), 1 `decision.proceed`.

The fleet tick is the most complete loop in the platform: kill switch → standby fence →
expire approvals → metrics → 37 sensors → validate due outcomes → execute approved → decide
→ learn → pressure (`fleet_autonomy_service.rb:132-216`); 17 real appliers; the
notify-lane-without-applier defect from August is closed by three independent mechanisms
including an equality oracle that asserts both arms (`proceed_lane_actuation_spec.rb:24-51`).

### 6.2 Present but not closing — the remedy half

| Loop | Scheduled | Closes with a remedy | Why not |
|---|---|---|---|
| Improvement discovery | **No** | No | `platform.discover_improvements` returns guidance text telling the caller which analyzers to run (`improvement_tool.rb:163-183`); no cron references it or `code_static_analysis` / `code_dead_code` / `code_find_duplicates` |
| Dev-improve execution | **No** | Partial | loop is `scheduling_mode: manual` with NULL `next_scheduled_at` (`improvement_promotion_service.rb:189-194`); `due_for_execution` can never select it; `RecommendationSensor` deliberately excludes code-quality offers (`recommendation_sensor.rb:57-61`) |
| Campaign discovery | 30 min | No | proposals need `approve!` with an actor |
| Campaign land | every min | **Yes** for `autonomous` campaigns | two hard pre-gates still run; deploy dry-run unless opted in |
| CVE intake → remediation | every min | Partial | rebuilds the artifact; rolling upgrade "declares `requires_approval` and returns `executed: false`, and nothing in the platform actuates it" (`cve_remediation_orchestration_executor.rb:413-415`) |
| Governance scan | 6 h | No | `MonitorService#auto_remediate!` has zero callers; collusion score maxes at 0.3 against a 0.7 threshold (`monitor_service.rb:192-207`) |
| Composite health sweep | 5 min | No | a `down` verdict triggers nothing — logged counts only (`system_platform_health_sweep_job.rb:41-47`) |
| Self-healing monitor | 10 min | 1 of 4 arms | `RemediationDispatcher` behind an unenabled flag; `check_stuck_workflows` exists and is never called |
| OODA closure / goals | 15 min | **Gated OFF** | SiteSetting `ai.autonomy.closure_driver_enabled` has no creator; deliberately excluded from the agent-writable registry |
| Self-challenge / LLM judge | **No** | No | see §6.3 |
| Skill evolution | weekly | **Yes, ungated, and inert** | see §6.3 |
| Module publication integrity | **No** | No | MCP verb only; no cron in either worker tree |

Threshold configurability (G10): 5 sensors are MCP-tunable via `SensorConfig`; **10 more are
DB-tunable through an account-settings ladder the MCP verb cannot see**
(`system_fleet_tool.rb:5919-5923` derives the catalog from `default_thresholds` only), so an
operator reading `get_sensor_config` concludes they are hardcoded; 21 are constants; 1 is ENV.

### 6.3 Built three times, wired zero times — the self-judgement half

| Loop | Built | Reaches a consumer |
|---|---|---|
| Skill usage → `effectiveness_score` | automatic on every in-platform run | **yes** — the one closed loop, blind to Claude Code self-reports |
| Skill evolution → served prompt | 4 verbs + 5 crons | **no** — `SkillVersion#activate!` flips flags and never copies `system_prompt` back to `ai_skills` (`skill_version.rb:49-54`); every runtime reader plucks `ai_skills.system_prompt` (`agent.rb:514`); the only live mutator is `SkillRefinementService#refine!:69`, reachable solely from the governance-gap path. **The operator-approval path has the same hole** (`improvement_recommender.rb:135-158`, `:185-190`): audited as applied, behaviourally inert |
| Self-challenge → anything | 3 verbs + service + scheduler + job | **no** — `generate_challenge!` creates a row at `generating` and enqueues nothing; the scheduler job is in no `sidekiq*.yml`; the agent grades itself with a 0.5 default on parse failure; no trust write, no skill write |
| LLM judge → evaluation → trends → benchmarks | service + rubric + parser + UI | **no** — never invoked; `ai_evaluation_results` is never written; the benchmark UI reports on an empty table |
| Trust score → gating | yes | **yes** — but fed only by execution metrics, never by either quality subsystem |

**Item 8 from August got worse.** `AiSkillAutoEvolutionJob` runs weekly, for every active
account, with no feature flag and no approval gate (`sidekiq.yml:672-677` →
`internal/ai/skills_controller.rb:56-69`; the `dev.skill_refine` gate lives on the MCP verb,
not on this internal endpoint). It creates A/B variants at 20% traffic that `EvolutionService`
genuinely serves (`evolution_service.rb:16-20`) while nothing writes the counters and nothing
schedules an end. Variants accumulate; incumbent always wins. Its blast radius is limited only
because what it writes is inert.

### 6.4 Live state of the loops today

| Read | Value | Reading |
|---|---|---|
| `get_system_health` | 0 active missions, 0 completed 24h, **0 agent execution events in 24h**, 28 active agents | platform-hosted LLM agents did no attributed work in the last day; the fleet tick runs as skill executors, not as agent executions |
| Campaigns | 13 total; **8 active, 6 of them with 0 tasks, no driver lease, no activity since 2026-09-08 20:09** | spawned from proposals and never driven; "a campaign never stalls" does not hold |
| Improvements | ~50 pending, ~50 approved-not-applied (oldest 2026-08-22), ~50 applied all on 09-07/09-08 | discovery runs in human-driven bursts; the approved backlog waits on a session; the "Improvement backlog drain" campaign has 0 tasks |
| dev-improve | 845 passed / 22 pending / 1 blocked / 0 in progress; 22 pending all created 2026-09-08 | the queue drains only when a session pulls |
| `query_learnings` | **0 rows for any keyword** (`platform`, `fix`, `deploy`); 50 rows with no query | the semantic branch (`compound_learning_service.rb:917-925`, threshold 0.5) returns nothing and the keyword fallback fires only when embedding generation returns nil — either learnings lack embeddings or the threshold excludes everything; either way the pull surface `BASE_GUARDRAILS` tells agents to use is empty for them |
| Learnings corpus | dominated by "CORRECTION to iteration N: fabricated review" (five instances) and per-tick "Fleet X → gate Y" rows | the highest-value learnings are about executor honesty; the automatic ones are shallow |
| Sensor config | 5 sensors listed, 0 overrides | thresholds have never been tuned through the door |
| Pending approvals | 6 `remediation_stuck` on `config_drift`, 3 `require_approval` (reprovision, boot-image drift, instance replace) | the platform is asking; the answer path is a human |

---

## 7. Systemic patterns

1. **Drift-then-rescue.** The largest correctness theme of the month was sensors that reported
   without measuring, docs that asserted false counts, and a discovery verb that describes
   analyzers rather than running them. Each was found by a human audit, not by the platform.
   The gate canary (`ai_gate_canary_job.rb`) is the only self-check of a self-check, and it
   only alerts.
2. **Exists-passes-review-never-executed** recurs in the skill lane three times (§6.3) and in
   the code-factory learning path, where both extractors call `extract_from_event`, a method
   that does not exist, and rescue the `NoMethodError` (`harness_gap_service.rb:97`,
   `remediation_loop_service.rb:163`).
3. **Silent no-ops.** Five flag-gated crons return `{skipped: true}` into a void; the
   integration-health sweep catches its own 403 and reports skipped; the health sweep's
   attribution execution is created terminal so the trust `after_update` hook never fires.
   `SiteSetting.get` returns nil for an uncreated key, so the OODA driver is off by absence,
   not by decision.
4. **Generated artifacts cost a second commit.** ~70 of 100 MCP commits are catalog
   regenerations; the 09-05 campaign recorded a catalog commit landing four minutes before the
   code it documented. The memory index already holds the rule (one owner, not a ban).
5. **The honesty layer is the strongest layer.** The evidence adjudicator, the equality oracle
   on proceed lanes, the fail-closed environment gate, the narrowing-only instance grant, and
   the `not_measured` discipline in the composite probe are all genuine and all landed this
   month. Where the platform lies today it is at read verbs (§4.2) and at write verbs that
   report success for an inert write (§6.3), not at gates.

---

## 8. Prescriptive remedies

Ordered by leverage against the vision, not by effort. Each names the seam to extend
(reuse-first) and the oracle that proves it closed — an assertion on the served value or the
executed side effect, never on a flag.

### 8.1 Give the platform a clock (closes "cannot improve itself without a session")

1. **Schedule discovery.** Add one worker cron (weekly, per account, kill-switch and
   environment gated) that runs `code_static_analysis`, `scripts/pattern-validation.sh`,
   `code_dead_code` and `code_find_duplicates` and files offers through `create_improvement`
   with the existing fingerprint dedupe. `discover_improvements` stays the LLM-facing guidance
   verb; the cron is the analyzer it currently only describes. Oracle: a seeded lint violation
   produces exactly one `Ai::ImprovementRecommendation` after one tick and zero after two.
2. **Let approved offers self-drain under a bound.** `improvement.enable_autonomy`
   (`improvement_tool.rb:346-371`) already exists and is off by default. Enable it for the
   `dev-improve` loop with a per-day budget and the existing `platform_drain_blocked?` refusals
   intact, once remedy 3 gives the driver an actuator. Until then, leave it off — a scheduled
   drain into a planning-only executor burns budget and mints attested records.
3. **Give the Platform Developer an actuator, or stop routing implementation to it.** Two
   options, in order of fidelity: (a) a loop-scoped `mission.repository` plus
   `tool_access.enabled = false` falls through to `GitToolExecutor` (Gitea-API commit) and
   unlocks `ai_test_execution_job.rb` — real diffs, real specs, one config change per loop;
   (b) a sandboxed Claude Code executor via `SandboxManagerService#exec_in_sandbox`
   (`sandbox_manager_service.rb:120`), which exists and is reachable only from
   `deploy_container_agent`. If neither, strip the red-first / `tsc --noEmit` lines from the
   canonical's prompt and make `campaign_delegate driver_kind: platform_agent` state that it
   produces plans, not diffs. Oracle: a delegated task ends in a commit SHA on the campaign
   branch and a `TestVerificationService` verdict of `verified`, not `attested`.
4. **Create the OODA switch and the dual-plane setting deliberately.** Seed
   `ai.autonomy.closure_driver_enabled` (default false) so the driver is off by decision, and
   surface both it and `control_plane_role_coordinator` on the operator settings page. Goals
   (item 9) come alive the moment the switch is on; nothing else is needed.
5. **Drive or archive the six empty campaigns.** Each was spawned 2026-09-08 with zero tasks
   and no lease. `campaign_delegate` to `claude_code` with an operator session, or archive.
   Approve or dismiss the ~50 approved-not-applied offers older than a week the same way;
   several are the security S1 findings from 08-29.

### 8.2 Close the self-judgement loops (or delete the claims)

6. **Skill evolution last mile.** `Ai::SkillVersion#activate!` must write
   `ai_skills.system_prompt` the way `SkillRefinementService#refine!:69` does, or every
   evolution verb and the operator-approval path must stop reporting `applied`. Fix the 20%
   vs `0.01..0.99` clamp mismatch at the same time. Oracle: after `activate_version`,
   `Ai::Agent#build_skill_system_prompts` returns the new text.
7. **Flag or remove `ai_skill_auto_evolution`.** Weekly, every account, no gate. Until remedy 6
   lands it is harmless only by accident; after remedy 6 lands it is an ungated live prompt
   mutation. Put it behind `dev.skill_refine` like the MCP verb, or delete the cron.
8. **Wire the LLM judge or retire the seat.** Call `EvaluationService#evaluate_execution`
   from the `dev_complete_task` verification path for `passed` outcomes, feed the result into
   trust `quality` and into `SkillVersion#record_outcome!` (which fixes item 8 at the same
   time); fix the flat-vs-nested schema mismatch; assert both arms. Otherwise delete the
   `reviewer` seat description that promises independent review of every drained task.
9. **Self-challenge: wire it or delete three verbs.** If wired: enqueue on
   `generate_challenge!`, grade with the judge not the challenged agent, remove the 0.5 default
   on parse failure, and write the result to trust. If not: delete
   `generate_self_challenge`, `list_challenges`, `get_challenge_result` and the two orphaned
   jobs so the surface stops advertising a capability that does nothing.
10. **Fix `query_learnings`.** Determine whether learnings carry embeddings on the control
    plane; if not, backfill through the existing re-embed path; if so, lower the 0.5 threshold
    or route through the keyword fallback on an empty semantic result rather than only on a nil
    embedding. Oracle: `query_learnings(query: "fabricated review")` returns the five
    correction learnings.

### 8.3 Make the read surfaces honest

11. **Export annotations from `declared_actions`** (`tool_catalog.rb:260-263`): `readOnlyHint`
    from `mutating: false` (fixes 179 missing and 3 wrong), `destructiveHint` from
    `DESTRUCTIVE_TOOL_PATTERNS` (72 tools), `idempotentHint` where the description already
    claims it. One change, ground truth already computed for all 634.
12. **`integration_health`:** persist `determine_health_status` through `update_health!`, and
    give the worker sweep a permission its JWT can carry or an internal route. Today the verb
    cannot fail differently and the "auto-pause" the schedule advertises never runs.
13. **`platform_resilience#failover_check`:** delete the three `rescue StandardError; []` or
    report `not_measured` the way `CompositeHealthProbe` already does in the same extension.
14. **Composite health `down` must trigger something.** Route a `down` verdict from
    `system_platform_health_sweep_job.rb:41-47` into a `Notification` and a fleet event, so the
    strongest probe in the platform is not write-only.
15. **`get_sensor_config` must list every DB-tunable sensor.** Extend `configurable_sensors`
    (`system_fleet_tool.rb:5919-5923`) to include the ten account-settings-ladder sensors, then
    migrate the 21 constants onto `SensorConfig` per the no-hardcoded-thresholds convention.

### 8.4 Make MCP a control plane for the platform itself

16. **Decide the identity boundary deliberately.** Either add read verbs for users, roles,
    permissions, invitations and the audit log (an agent that writes audit rows should be able
    to read them), or document in `mcp-and-tools.md` that identity is intentionally
    operator-only. Today it reads as an omission.
17. **Add `request_approval` / `respond_to_approval`** on `Ai::ApprovalRequest`, the core model
    with no direct door. The fleet lane mints these every tick; agents cannot answer them.
18. **LLM providers, model catalog, schedules, webhooks:** add list/get at minimum; these are
    the four families an operations agent most often needs and cannot reach.
19. **Migrate the system extension onto `register_extension_tools`** — 263 hardcoded entries.
20. **Filter the docs catalog through `advertised_action?`** (`mcp_tool_catalog.rake:26`) or
    relabel it as a structural map rather than a grant-sizing surface.

### 8.5 Guardrails and lint

21. **Add a verification-gate line to `BASE_GUARDRAILS`** so the 30 canonicals outside the dev
    loop are told to verify by execution before reporting done; update the
    `bootstrap_verbs_spec` derivation if a new verb is named.
22. **Model-id lint** in `spec/lint/` with a path allowlist for the catalog files, scanning
    `server/`, `worker/` and `extensions/`. The `|| "model-id"` shape is 92% precise; start with
    the twelve Class-A fallbacks and `devops_integration.rb:11`.
23. **Fix HIER-P0** (`ai_agent_hierarchy_seed.rb:90-95`): an empty `allowed_delegate_types`
    must mean "none", not "any", or the nine leaves need an explicit list.
24. **Record skill usage from `record_agent_execution`** so Claude Code runs reach
    `skill_health`.
25. **Backfill the thin destructive descriptions** (`delete_skill`, `toggle_skill`,
    `system_cancel_task`, `docker_restart_container`, `dismiss_notification`).

### 8.6 Documentation truth

26. Regenerate the four count claims from the catalog (`README.md:20`,
    `extensions/system/README.md:289-291`, `:105-110`) under the existing drift guard; remove
    the stale systemd unit form from `agents-and-autonomy.md:1151` and
    `use-powernode-from-claude.md:105`; qualify "self-improving" in
    `extensions/system/README.md:12` until remedies 1–3 and 6–8 land.

---

## 9. Decisions the operator owns

1. **Which actuator the Platform Developer gets** (remedy 3a, 3b, or none). This decides
   whether "autonomous implementation" means the platform or means Claude Code. Every other
   drain remedy depends on it.
2. **Whether to turn on the OODA closure driver** once its setting exists (remedy 4). It is the
   only path that advances goals, and it was gated off by absence rather than choice.
3. **Wire or delete: judge, self-challenge, skill evolution.** Three subsystems, each a few
   thousand lines, each currently a claim. Keeping them as claims is the option to reject.
4. **The identity boundary over MCP** (remedy 16).
5. **Disposition of the six empty campaigns and the approved backlog older than a week**
   (remedy 5) — the bulk-operation rule applies; each needs a listed decision, not a category.
6. **Whether `ai_skill_auto_evolution` runs at all** before remedy 6 lands.

---

## Appendix — evidence base

Scratch reports produced by the five sweeps (session-local, not tracked): commit digest
(21 themes, 684 lines), vision claims (63 claims, 15 loops, 15 contradictions), MCP surface
(634 actions, REST-vs-MCP table, 25 diagnosis verbs traced), agent prompts (32 agents, 117
skills, criteria table, executor path), introspection loops (95 cron entries, 37 sensors,
nine-wire re-score). Live reads: `get_system_health`, `list_improvements` ×3,
`campaign_list`, `campaign_status`, `dev_list_tasks` ×3, `query_learnings` ×5,
`system_recent_signals`, `system_get_sensor_config`, `list_agents`, `search_knowledge`, all
at 17:30–17:35 UTC on 2026-09-10 against the production connector.
