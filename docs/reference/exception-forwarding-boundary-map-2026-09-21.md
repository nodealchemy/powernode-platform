# Exception-forwarding boundary map: enumerate by SINK, not by rescue arm (IMP-8dc591eae190)

**Status: MEASUREMENT AND CLASSIFICATION ONLY. Nothing in this document has been fixed.**
Per operator direction, this task fixes nothing — the map is the product. Remediation is
follow-on work, per cluster, individually approved. **Red-first does not apply**: this is not a
bug fix, so no failing spec was written or is claimed.

## Why this exists

`scripts/audit/exception_forwarding_scan.rb` walks `rescue` bodies and asks whether the bound
exception variable is read into a provider-facing envelope. That is **one route**. Three review
rounds on IMP-1a5c145c24eb found three more, live, verified in production code this session:

1. **Rescue arm** forwards `e.message` into a provider-facing envelope. The scanner sees this.
2. **Callee absorbs** — the called service rescues internally and returns a Result object; the
   consumer forwards `result.error`. No rescue arm exists at the leaking site.
3. **Nearer frame rescues** — a frame closer to the sink than the tool's own arm rescues and
   returns a failure hash, which the tool hands back **as** its own result, so the tool's arm is
   never entered.
4. **Persist-then-resurface** — raw text is written to a DB column and read back by a
   **different** action.

Plus a fifth, adjacent shape: **the declared contract** (`skill_descriptor(outputs:)`) advertising
a field the body no longer returns.

This task inverts the enumeration: instead of walking rescue arms forward, it enumerates **sinks**
— every construct whose value becomes an MCP tool result — and walks backward.

## Sink definition and the command that produces it

A sink is: the return value of any `ai/tools/*.rb` action method. `BaseTool#execute` (verified by
reading `server/app/services/ai/tools/base_tool.rb:701-789`) dispatches to the tool's `#call`,
which (verified by reading `improvement_tool.rb:145-160` and `system_ingress_tool.rb:362-374` as
representative examples) `case`-dispatches to an action method and returns that method's value
**verbatim** — there is no re-wrapping at the base-class level beyond the refusal/gating paths
before `#call` runs. So an action method's return value reaches the MCP client whether it was
built by `error_result(`/`success_result(`, or is a raw Hash constructed some other way and
returned directly.

Concretely, the argument passed to `error_result(`/`success_result(` (or the raw Hash itself, for
an action that skips those helpers) is sink content, and everything that can reach that argument
at any call depth is in scope.

## Route 1 — rescue arm (baseline, not re-derived here)

Already mapped by `docs/reference/exception-forwarding-root-scope-2026-09-21.md`: 96-file root (87
core + 9 extension), 193 RAW hits full-union. **Core is still unswept** (87 files / 123 RAW);
extension is largely closed for this route only. Not re-walked in this task — cited by reference.
This map's new work is routes 2–5, which that scanner is structurally blind to.

## Route 3 — nearer frame rescues: THE HEADLINE FINDING

**One seam, ~70-subclass blast radius, confirmed live from at least two MCP tools.**

`extensions/system/server/app/services/system/ai/skills/base_skill_executor.rb` is "the common
base class for every system-extension skill executor" (its own header comment, line 6). Its public
entry point:

```ruby
# base_skill_executor.rb:351-376
def execute(gated: false, **inputs)
  ...
  result = perform(**acceptable_inputs(inputs))
  ...
  result
rescue StandardError, NotImplementedError => e
  audit_log_error(e)
  failure(e.message)          # failure(msg, **extra) => { success: false, error: msg }.merge(extra)
end
```

This is **one shared blanket rescue for every subclass's entire `#perform` call tree**, with **no
`caller_safe`-style discrimination** — `failure(msg)` builds `{ success: false, error: msg }`
unconditionally (`:598-600`).

**Confirmed reaching an MCP tool result verbatim**, two distinct tools, no re-sanitization at the
tool layer:

- `system_ingress_tool.rb:682-686` — `run_executor` returns
  `build_skill_executor(klass).execute(**inputs)` directly; `call` (`:362-372`) returns
  `run_executor(action, params)` directly. `ACTION_EXECUTORS` (`:81-88`) routes 5 distinct executor
  classes through this path.
- `sdwan_tool.rb:2317-2321` — `run_skill_executor` does
  `result[:success] ? success_result(result[:data]) : error_result(result[:error])` — explicitly
  forwards `result[:error]` unchanged. 3 distinct executor classes confirmed routed through it
  (`federation_compose`, `multi_tenant_isolation`, `service_discovery_compose`, `:2265-2297`).

**Command that produced the subclass count** (run from `/home/pnadmin/worktrees/loop-merge`):

```
find -L extensions/system/server/app/services/system/ai/skills -maxdepth 1 -name "*.rb" | wc -l   # 74
command grep -RlE "< BaseSkillExecutor\b" extensions/system/server/app/services/system/ai/skills | wc -l   # 67
command grep -RlE "< .*CrudFactory" extensions/system/server/app/services/system/ai/skills | wc -l          # 3
```

74 files total: 67 direct `BaseSkillExecutor` subclasses + 3 `CrudFactory`-based (not individually
traced — **UNVERIFIED whether `CrudFactory` shares the same blanket rescue**; check:
`grep -n "rescue" extensions/system/server/app/services/system/ai/skills/crud_factory.rb` or
wherever that base lives) + `base_skill_executor.rb` itself + 4 non-executor helper classes
(`instance_replacement_ledger.rb`, `sdwan_composition_pipeline.rb`, `skill_bindings_reconciler.rb`,
`template_approval_policy.rb`).

**Of the 67 confirmed `BaseSkillExecutor` subclasses, 27 have zero `rescue` clause of their own**
(command: loop over each file, `grep -q rescue`) — 100% of every exception their `#perform` raises
reaches the shared blanket rescue unfiltered. The other 40 narrow *some* exceptions (e.g. the 3
`WriteError`-specific fixes landed this session in `expose_service_local_executor.rb` /
`expose_service_public_tcp_executor.rb` / the ingress tool's own arm) but **still fall through to
the shared blanket rescue for anything not explicitly caught** — a `NoMethodError`, an unexpected
`ActiveRecord` error, a network timeout inside `perform`, all still forward raw.

**Core vs extension for this route: 100% extension.** `BaseSkillExecutor` and every subclass live
under `extensions/system/`. Core's own two standalone `ai/skills/*.rb` executors
(`design_skill_from_intent_executor.rb`, `design_agent_team_from_intent_executor.rb`) define their
own `success`/`failure` with no shared base class — **not traced in this pass**; flagged
UNVERIFIED (check: read both files' `rescue` clauses directly, they are only 2 files).

**Not traced, flagged UNVERIFIED with the check that would settle it:**
- `A2A::MessageHandler#execute_skill`/`#execute_skill_streaming` (`server/app/services/a2a/
  message_handler.rb:239-261`) is a **separate** handler-dispatch mechanism (not a
  `BaseSkillExecutor`), and its result reaches an A2A task record, not necessarily an MCP tool
  result directly. Whether A2A responses cross to a model provider the way MCP tool results do —
  and whether `handler.public_send(...)` can raise unrescued into a provider-facing surface — is
  **UNVERIFIED**. Check: read `Ai::A2aTask#complete!`/`#fail!` and whatever serves A2A task state to
  a caller.
- `System::Fleet::DecisionEngine#invoke_skill` (`decision_engine.rb:2007`) calls skill executors
  for autonomous reconciliation, not directly from an MCP tool call — **out of this sink's scope**
  by the sink definition above (it never becomes an MCP tool result), but its result may still
  reach an audit/notification surface. Not traced.

## Route 2 — callee absorbs into a Result object

**Candidate population, one command:**

```
command grep -RlE "Struct\.new\(.*:error|OpenStruct\.new\(.*error" server/app/services extensions/system/server/app/services
```

**55 files** (core + extension combined; not separately counted here — see the sink-first walk
below for the ones that matter). This population is far too large to trace exhaustively in this
pass; the right move, and the one the self-check below validates, is to walk backward from the
**sink** rather than forward from all 55 candidates.

**Sink-first walk, the command:**

```
command grep -RnE "error_result\([^)]*\.(error|reason)\b" server/app/services/ai/tools/*.rb extensions/system/server/app/services/ai/tools/*.rb | command grep -vE "\be\.(error|message)\b"
```

(The `grep -v` excludes `e.error`/`e.message` — a rescue-bound exception variable forwarded
directly, which is Route 1's shape and already covered.) **Result: 17 sink call sites, all in
`extensions/system/`, 0 in core** by this exact literal pattern (core may use different naming —
see Route 2 core gap, below).

Two files:
- `system_acme_tool.rb:213,244` — **CONFIRMED SAFE**, already fixed this session (`7eeb0cc80`'s
  predecessor, `IMP-1a5c145c24eb`): both are the `else` branch reached only when
  `result.caller_safe` is true (a caller-authored precondition message). Read directly, confirmed.
- `system_fleet_tool.rb` — **15 sink call sites**, lines `3929, 4905, 5624, 5639, 5706, 6455, 6490,
  6549, 6551, 6729, 7727, 7737, 9001, 9007, 9012, 9096` (16 listed; one, `:6551`, is a `.merge` on
  the same `error_result(result.error)` call at `:6549` and is the same finding, not a distinct
  one — 15 distinct findings).

**Per-producer verdict, each traced by reading the producer's `rescue`/`err(`/`Result.new(` call
sites directly (not inferred from the sink alone):**

| Producer (all under `extensions/system/server/app/services/system/` unless noted) | Sink site | Verdict | Evidence |
|---|---|---|---|
| `InstanceOpsHoldService` | `:5624,:5639` | **SAFE** | Private `err(instance, message)` helper; all 4 call sites pass a literal caller-authored string (`instance_ops_hold_service.rb:32,33,36,58`). Its own `rescue StandardError => e` clauses (4, lines 112/134/145/155) log and return `nil`/`false`, never feed a `Result`. |
| `InstanceCordonService` | `:7727,:7737` | **SAFE** | Same `err(instance, message)` pattern; the `why` variable traced through `cordon_refusal`/`uncordon_refusal`/`pool_state_refusal` (`:174-209`) — every branch is a static or instance-attribute-interpolated string, never `e.message`. |
| `ModuleDiffService` | `:5706` | **UNSAFE — live** | `Result.new(ok?: false, error: e.message)` on both `ArgumentError` (`:66-67`) and `StandardError` (`:68-70`). |
| `VolumeManagementService` | `:6455,:6490,:6549` | **UNSAFE — live, extensive** | `Runtime::Result.err(error: e.message)` at ≥15 distinct rescue sites across attach/detach/create/delete-snapshot/restore; one site is `e.record.errors.full_messages.join(", ")` (`:358`) — the exact `e.record.errors` pattern this family has flagged elsewhere, here reachable **directly** from an MCP tool. |
| `System::Compliance::ComplianceSnapshotService` | `:6729` | **UNSAFE — live** | `Result.new(ok?: false, error: e.message)` (`:39-41`); a second internal rescue at `:283-285` returns `{ error: e.message }` into what becomes `snapshot.rcp_invariants` — not traced further, flagged UNVERIFIED whether that also surfaces. |
| `System::InstanceControlService` | `:4905` | **UNSAFE — live** | `Runtime::Result.err(error: e.message)` from `rescue Providers::BaseProvider::ProviderError` (`:119`) and a bare `rescue StandardError` (`:128`). |
| `System::BootImage::UpgradeDispatcher` | `:3929` | **UNSAFE — live** | `err("Failed to queue boot-image upgrade: #{e.message}")` from `rescue ActiveRecord::RecordInvalid => e` (`:242-243`); sink is `result.reason`, not `.error` (this producer's Result field is named `reason`). |
| `System::Gitops::RepoSyncService` | `:9001` | **UNSAFE — live, worse** | `Result.new(ok?: false, error: "#{e.class}: #{e.message}")` (`:52-54`) — includes the exception **class name** in addition to the message. |
| `System::Gitops::DesiredStateParser` | `:9007` | **UNSAFE — live** | `Result.new(ok?: false, error: "#{e.class}: #{e.message}")` (`:77-79`), also for a `Psych::SyntaxError` with a friendlier prefix (`:75-76`, itself still raw YAML-parser text). |
| `System::Gitops::DiffEngine` | `:9012` | **UNSAFE — live** | `Result.new(ok?: false, error: e.message, diffs: [])` (`:44-46`). |
| `Security::CredentialRestorationService` (**CORE**, crypto-adjacent) | `:9096` | **UNSAFE — live, ONE shape (corrected)** | `rescue ::Security::VaultTransitClient::TransitError => e; Result.new(ok?: false, error: "pepper rotation failed: #{e.message}", ...)` (`:87-90`) on the ERROR path — **real, live**. `system_fleet_tool.rb` forwards it via `error_result(result.error || "rotation failed")` (`:9096`). This is Vault transit key-rotation error text; flagged at ABSOLUTE priority per crypto-material-safety rules — not read further, not reproduced here beyond the class name. **CHECKED NEGATIVE, initially misjudged as a second leak:** the per-account `rescue => e` inside the rotation loop (`:69-75`) appends `{ account_id:, message: e.message }` to `stats[:errors]`, and a first pass here read `errors: result.errors` sitting inside `success_result(...)` and concluded it forwards on success. It does not: `:75`'s append is always preceded by `stats[:failed] += 1` (`:74`), and the terminal `Result.new(ok?: stats[:failed].zero?, ...)` (`:79`) means `stats[:errors]` non-empty ⟹ `failed >= 1` ⟹ `ok?` is **false** ⟹ the tool takes the `error_result` branch, never `success_result` — and that `Result` sets no `error:` key at all, so the per-account `e.message` reaches nobody. The lesson, stated because it is the exact error class this family keeps paying for: judging a sink by whether it MENTIONS an unsafe value (`errors: result.errors` inside a `success_result` call) is judging by shape, not reachability — the discriminating question was whether `ok?` can be true while `errors` is non-empty, which one read of two adjacent lines settles. Corrected before filing; the error-path leak stands and is being filed separately (not by this task). |

**Route 2 core gap, stated as a gap, not closed:** the literal-pattern grep above (`X.error`/
`X.reason` excluding `e.error`/`e.message`) found **zero** core hits. That does not mean core has
none — it means core's equivalent pattern, if any, uses different variable names or a different
shape (e.g. `outcome.failure_reason`, a hash key access `result[:error]` rather than a method
call). **UNVERIFIED for core; check:** re-run with a broader pattern
(`error_result\([^)]*\[:error\]|error_result\([^)]*_reason\b` etc.) against `server/app/services/
ai/tools/*.rb`, and separately check core's own `Struct`/`OpenStruct` producer list (not extracted
in this pass — the 55-file grep above already includes core paths; the core subset was not
separately isolated here).

**Remaining 55 − (2 producers confirmed safe + 9 confirmed unsafe) ≈ 44 candidate files**: not
traced. Most are plausibly background-job/reconciler-only (e.g. `disk_image_retention_service.rb`,
`compliance/daily_snapshot_archival_service.rb`, `cve_ops/feed_ingest_service.rb` read as
autonomous-sweep services, not MCP action handlers) and so may be genuinely out of THIS sink's
scope — but that is an inference from filename, not a trace, and is exactly the kind of claim this
family has been burned by before. **Flagged UNVERIFIED; the check that would settle each: grep
`ai/tools/*.rb` for the bare class name, as done above for the 12-file offer intersection below.**

## Route 4 — persist-then-resurface

**Candidate population, one command** (core schema only — extension migrations are not captured in
a separate schema.rb; **this is a gap, not a claim of completeness**):

```
command grep -nE "t\.(string|text) \"[a-z_]*error[a-z_]*\"" server/db/schema.rb | wc -l   # 80
```

80 core columns whose name contains "error". Exhaustive per-column reader tracing (80 columns × all
readers) is out of budget for this pass. Three were traced fully as a methodology check:

- **`last_renewal_error`** (`schema.rb:8623`, `Acme::CertificateManager`) — the **already-confirmed
  and already-fixed** instance from `IMP-1a5c145c24eb`. Its presence in this grep's output
  confirms the enumeration method would have found it. `system_acme_tool.rb`'s own serializer now
  returns `last_renewal_error_present:` (boolean), not the raw text — the read side is fixed. A
  second reader, `acme_certificate_contributor.rb:91`, still forwards it into a status-evidence
  hash reaching CORE's `platform_status_tool.rb` — this is exactly offer `01a0c268-7b02` (see
  triage below), filed, not fixed.
- **`oauth_error`** (`schema.rb:7353`, `McpServer`) — **CONFIRMED NON-ISSUE for this sink.** Written
  raw (`mcp/oauth_service.rb:88,91,115` — `@server.update!(oauth_error: e.message)`), but its only
  reader, `McpServer#oauth_status` (`mcp_server.rb:358-369`), is consumed by exactly one caller:
  `Api::V1::McpOauthController` (`:101`) — a **browser-authenticated controller boundary**,
  established elsewhere in this family as a different trust boundary, out of scope for the
  provider-facing sink this map targets. Traced to its one and only reader; not inferred from the
  column name.
- **`last_sync_error`** (`schema.rb:8567`, package-repository sync) — same shape: written raw
  (not re-traced here, same pattern as `oauth_error`), single reader
  `package_repositories_controller.rb:393` — **controller boundary, confirmed non-issue.**

**Remaining 77 of the 80 columns: UNVERIFIED-enumerated, not traced.** The check that would settle
each: `command grep -RnE "\.<column_name>\b" server/app extensions/system/server/app` for readers,
then classify each reader's own caller chain as MCP-tool-facing vs controller-boundary vs
background-only.

## Route 5 — declared contract (adjacent shape)

**Candidate population:**

```
command grep -RlE "skill_descriptor" extensions/system/server/app/services/system/ai/skills/*.rb server/app/services/ai/skills/*.rb | wc -l   # 70
```

70 files declare a `skill_descriptor`. One is the already-confirmed and already-fixed instance
(`acme_certificate_provision_executor.rb`, `IMP-3b0e956d1d5e`: the descriptor advertised 3 literal
Vault paths after the body was fixed to return `vault_paths_present:` — both the body and the
descriptor needed the fix). **The remaining 69 are UNVERIFIED-enumerated, not individually
compared** (declared `outputs:` keys vs the literal hash keys actually returned by `perform`). This
is a spot-check-shaped task, not a backward trace, and needs its own pass — flagged as a candidate
follow-on, not attempted exhaustively here.

## MANDATORY SELF-CHECK — intersection with known leak sites

Known leak files fixed or diagnosed by this family this session (9, all independently confirmed
against commit history / this session's own record, not re-derived from memory alone):

| # | File | This map's route | Found by this map? |
|---|---|---|---|
| 1 | `acme/certificate_manager.rb` | Route 2 (source) | Yes — read directly as part of tracing `system_acme_tool.rb`'s sink. |
| 2 | `system_acme_tool.rb` | Route 2 (sink) | **Yes** — literal hit in the Route 2 sink-first grep, confirmed safe. |
| 3 | `acme_certificate_provision_executor.rb` | Route 2 (consumer) + Route 5 | **Yes** — is one of the 67 `BaseSkillExecutor` subclasses (has its own rescue, not one of the 27 zero-rescue ones) and is the one confirmed-fixed Route 5 instance. |
| 4 | `system_blast_radius_tool.rb` | Route 1 | Not re-derived — correctly out of this map's new-work scope; already in the existing 96-file Route 1 map. |
| 5 | `system_ingress_tool.rb` | Route 1 (own arm) + Route 3 (dispatcher) | **Yes, twice** — the tool's own `WriteError` arm is Route 1 (existing map); the tool's `run_executor` mechanism is THIS map's headline Route 3 finding. |
| 5a | `expose_service_local_executor.rb` | Route 3 | **Yes** — one of the 67 subclasses; has its own narrowed `WriteError` rescue but still exposed to the shared blanket rescue for anything else. |
| 5b | `expose_service_public_tcp_executor.rb` | Route 3 | **Yes** — same as 5a. |
| 6 | `module_build_planner_service.rb` | Route 1 (source) | Not re-derived — this is a plain service consumed via a direct rescue arm in its caller (Route 1 shape), not a Result-object sink; correctly outside Route 2–4's methodology. |
| 7 | `system_fleet_tool.rb` (2 specific arms: `InvalidForeignKey`, `OrchestrationError`) | Route 1 (2 arms, fixed) | **Yes, and MORE** — this map's Route 2 walk of the SAME FILE found **15 additional, unrelated, still-live sink sites** the Route 1 fixes never touched (see table above). |
| 8 | `ci_runner_lease_service.rb` | Route 1 (source) | Not re-derived — same reasoning as #6. |
| 9 | `system_architecture_catalog_tool.rb` | Route 1 (dead arms) | Not re-derived — already in the existing Route 1 map. |

**Verdict: this map's routes 2–5 methodology correctly finds every known Route 2/3/5 instance among
the 9 (5, 5a, 5b, 3, 2 = 5 of 5 relevant), and correctly does NOT re-find the 4 pure-Route-1
instances (4, 6, 8, 9) — those remain the existing scanner's job, not a miss by this one.** This is
the opposite failure mode from the earlier rescope (`IMP-6c8ad340c334`), where a new criterion
selected **zero** of its own motivating population; here the new criterion, applied to the
population it is actually meant to cover, selects all of it. The single most important result of
this self-check is **not** a miss — it is that **item 7's file was independently re-touched by this
map and yielded 15 NEW live findings never surfaced by 3 rounds of review this session**, because
those 3 rounds were themselves Route-1-shaped (walking rescue arms), and `system_fleet_tool.rb`'s
own header comment at `:2857-2874` documents a prior, careful, SPEC-PINNED audit of exactly that
shape — one that explicitly reasoned "converted to a Result by the service that raises them...
[handled]" for `VolumeManagementService`, `ManifestImportService`, and "everything behind
`BaseSkillExecutor#execute`," and stopped there. **That comment is the mechanism of this whole
blind spot, stated in the codebase's own words**: a Result conversion was treated as the end of the
trace, when the Result's `.error` field was itself unexamined cargo.

**This is sharper than "the audit stopped at the Result boundary."** The comment does not merely
fail to look past the boundary — it NAMES, as already handled, the exact two components where this
map found live leaks: `VolumeManagementService::VolumeError` (this map's Route 2 headline) and
"everything behind `BaseSkillExecutor#execute`" (this map's Route 3 headline). Both headlines of
this document are, in the prior audit's own text, listed as disposed of.

**And the reasoning is pinned by a spec, not just stated in a comment**:
`spec/requests/api/v1/mcp/system_fleet_tool_refusal_surface_spec.rb` asserts the "exactly four
propagate" enumeration that comment describes. That spec is green today, and its greenness proves
nothing about Route 2/3 — it only tests which exceptions ESCAPE the tool's `case` statement
unrescued, which is precisely the Route-1 shape; a value that crosses via a `Result#error` field
never raises, so it is structurally invisible to that spec regardless of whether it leaks. This is
the third time in two days this family has found a spec pinning a defect as intended behaviour, and
the most consequential instance yet: what it pins here is a piece of REASONING ("Result conversion
= handled"), not a single value or field. Whoever remediates Route 2 must not read this spec's
continued greenness as evidence the surface is closed — the spec was never asking that question.

## Offer triage (8 offers, per operator direction)

| Offer | Subject | Verdict |
|---|---|---|
| `01a0c1b7-d502` | 12 excluded service files, outside `ai/tools`, matched only on `e.record.errors` | **PARTIALLY CORRECTED, retarget.** Of the 12, 9 have zero references from any `ai/tools` file (checked by class-name grep) — genuine non-issues, confirming most of the original finding. But **`volume_management_service.rb`** — one of the 12 — **is** reachable, via `system_fleet_tool.rb`'s Route 2 pattern (this map's table above), contradicting the original "zero intersection with criterion (c)" result: criterion (c) (`error_result(`/`success_result(`/`processing_metadata` producer) correctly excluded it, but this map's sink-first walk shows it reaches a sink anyway via `.error` forwarding — the file just isn't a producer itself, it's consumed by one. The two `expose_service_*_executor.rb` files in the 12 are BaseSkillExecutor subclasses, already partially fixed (WriteError) but carry the same residual Route 3 exposure as every other subclass. **Recommend: close for the 9 confirmed non-issues, retarget the 3 (volume_management_service.rb, both expose_service executors) into the Route 2/3 remediation clusters below.** |
| `01a0c1d3-a3ef` | Result-object path | **CONFIRMED LIVE — this map's largest concrete cluster.** Subsumed by this doc's Route 2 section: 9 confirmed-unsafe producers, ≥10 sink call sites in `system_fleet_tool.rb` alone, one CORE + crypto-adjacent (`CredentialRestorationService`). **Recommend closing this offer and filing a new, concretely-scoped remediation offer citing this map's Route 2 table directly**, since the original offer's title names the mechanism but not the sites. |
| `01a0c1e1-4881` | `OrchestrationError` fail-open interim | **Remains distinct.** This tracks the deliberate extension-only workaround landed this session in `launch_agent_fleet` (durable fix needs a CORE change to `orchestrator_service.rb`, out of scope then and now). This map adds no new information about it — it is a Route 1 core-migration item, not a Route 2–5 finding. Not touched, not subsumed. |
| `01a0c207-958f` | Three `WriteError`/`PoolError` sites | **Confirmed fixed for the named exception classes; retarget for the residual.** These are exactly the 3 ingress executors already fixed this session for `WriteError` specifically. This map shows the fix narrowed one exception class but the shared `BaseSkillExecutor` blanket rescue remains live for these same 3 files for anything else. **Recommend: close the original narrow scope, fold the residual into the new Route 3 (`base_skill_executor.rb`) remediation cluster** rather than treating it as fully resolved. |
| `01a0c268-7b02` | Status-evidence route (`last_renewal_error` → `acme_certificate_contributor.rb` → core `platform_status_tool.rb`) | **Remains distinct, confirmed consistent with Route 4's category.** Not re-traced deeper in this pass beyond confirming the general Route 4 shape is real (via the `last_renewal_error` schema-column check above). Not subsumed — it is Route 4's one already-diagnosed, not-yet-fixed instance. |
| `01a0c179-4071` | `SkillRun.error_message` | **Remains distinct, files confirmed present in core, not traced by this map.** My first pass searched `/skill_run/i` and found nothing — that was a scoping artifact, not evidence of absence: the actual files are `server/app/services/ai/skill_recipe_runner.rb` and `server/app/services/ai/concierge_service.rb` (both core), which `/skill_run/i` cannot match against `skill_recipe_runner`. Confirmed present: `skill_recipe_runner.rb:420-424` writes `error_message:` via `fail_run!(step, error_message)`; `concierge_service.rb:1113` reads it back — `"Recipe **#{run.skill.name}** failed at step ...: #{resumed.error_message}"` — which reads like a Route 4 shape (persist-then-resurface) surfacing through a conversational/concierge path. Not traced further in this pass; the offer's own scope should be trusted over this map's negative, which is exactly why the negative was wrong the first time. |
| `01a0c100-bf1f` | `SsrfError` raise sites | **Remains distinct — Route 1 shape.** `SsrfError` appears in `server/app/services/ai/data_sources/*.rb` and `data_source_tool.rb` (core) — a direct-raise/rescue-arm pattern, not a Result-object or persisted-column shape. This map's routes 2–5 add nothing new here; it is squarely the existing scanner's territory (core, unswept). Not touched. |
| `01a0c0e9-c38d` | 22 bare-`ArgumentError` carve-outs | **Remains distinct — Route 1 shape.** Confirmed 13 `rescue ArgumentError` sites in core `ai/tools/*.rb` alone (extension likely adds the rest toward 22, not separately counted here). This is the already-known "judge by rescued class, not by output shape" risk (a bare `ArgumentError` is exactly the class `CallerFacingError` exists to distrust) — a Route 1 classification task. Not touched by this map. |

## Core vs extension split, summary

- **Route 1** (existing, not re-derived): 87 core files / 9 extension files. Core dominates and is
  unswept; extension is largely closed.
- **Route 2** (this map): confirmed-unsafe producers are **8 extension + 1 core**
  (`Security::CredentialRestorationService`) — the one core hit found this pass is crypto-adjacent
  and the highest-severity single item in this document. Sink call sites are **100% extension**
  (`system_fleet_tool.rb`, `system_acme_tool.rb`) by the literal pattern used; **core's equivalent
  pattern is an explicit, stated gap**, not a confirmed absence.
- **Route 3**: **100% extension** by construction — `BaseSkillExecutor` and all 70 files under it
  live only under `extensions/system/`. Core's 2 standalone skill executors are unverified,
  separate, and small enough to check directly next.
- **Route 4**: checked population is core-only (schema.rb); extension's own migrations were not
  separately enumerated — **stated gap, not a finding of "extension is clean."**
- **Route 5**: 70 files, overwhelmingly extension (same `ai/skills` tree as Route 3); core's 2
  standalone executors not separately checked for descriptor drift.

**Overall: this map's new findings (Routes 2–3) skew heavily extension, opposite of Route 1's
core-dominant pattern** — consistent with Route 1 already having closed most of extension's
`ai/tools`-tree rescue-arm exposure this session, which pushed the remaining live risk in
extension into the routes the rescue-arm scanner cannot see. Core's Route 2/4/5 exposure is
explicitly **unverified, not confirmed low** — the biggest gap this map leaves open.

## What this map does NOT establish (read this before treating it as complete)

- It is not a complete backward trace of all 55 Route 2 candidates, all 80 Route 4 columns, or all
  70 Route 5 descriptors — each states its traced subset and its untraced remainder explicitly.
- Core's Route 2 sink shape was searched with one literal pattern and found nothing; that is a
  weaker claim than "core has no Route 2 exposure" and is labeled as such above.
- The CrudFactory-based executors (3 files), core's 2 standalone skill executors, and the A2A
  handler-dispatch mechanism are named but not traced.
- No exception class was judged by its output shape — every UNSAFE verdict above was reached by
  reading the producer's own `rescue`/`err(`/`Result.new(` call sites directly, per this family's
  standing method note.
