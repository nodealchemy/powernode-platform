# System Extension Discovery Review — Modules, Templates, Repository Index/Search, Purpose-Driven Node Building

**Date**: 2026-08-03 · **Type**: high-level review/discovery (report only; nothing implemented)
**Scope**: `extensions/system` — module discovery/design/creation, template creation, the
repository index/search functionality, and the agent-facing path "discover relevant packages
by purpose and build a node for a particular use", especially when no such module/node has
been designed before.
**Method**: four parallel read-only source explorations (module lifecycle, templates,
package index/search, agent discovery surface) + platform MCP knowledge queries. The
sharpest claims (§5, §6) were independently re-verified against source before publication.

> **Status addendum (2026-08-04).** This document is the original report and is left as
> written — it records what was true on 2026-08-03, including any claim later corrected.
> It did not stay report-only: the operator subsequently approved a subset of §7 and §8
> through `/improve`, and those were implemented and reviewed as a two-wave `dev-improve`
> campaign. Do not read §7/§8 as an open to-do list — check the improvement queue
> (`platform.improvement` `list_improvements`) for the current state of any item before
> acting on it. Two items were deliberately NOT taken and remain open operator decisions:
> the instance-principal permission-tier-skip **policy fork**, and the **declarative
> module-authoring seam** (§7).

---

## 1. Executive summary

**The platform has production-quality purpose-based discovery in exactly one place: the
package catalog.** apt/rpm packages are synced, trigram-indexed, and pgvector-embedded
(HNSW cosine), searchable lexically/semantically/hybrid, and discoverable by free-text
intent with confidence buckets. From a discovered package, an agent can preview the
dependency closure, materialize a `NodeModule` graph, create a template, assign modules,
and provision an instance — steps that are all agent-reachable MCP today.

**Everything before and around that spine is missing or disconnected:**

1. **Modules and templates have no purpose search.** `NodeModule` has no embedding column;
   `system_list_modules` filters by `variety` only; `system_list_templates` takes no
   parameters at all. An agent cannot answer "does a module/template for X already exist?"
   by purpose — the reuse-first gate the authoring runbook demands has no machine surface.
2. **No agent can author a module from scratch.** Module creation requires a git commit of
   `modules/<slug>/manifest.yaml` (+ usually a hand-written `stage15.sh` arm); no MCP tool
   can write a file to a repo, and four independent gates (CI slug check, git-tracked
   filter, planner's `manifest_yaml`-non-blank intersection, orchestrator lookup) each
   confine agents to rebuilding modules that already exist.
3. **The "author a module" conclusion is computed and then discarded at three separate
   points** (§6): the capability resolver returns unresolved requirements that are never
   persisted; `CapabilityGapSensor` emits a signal no `DecisionEngine` binding consumes
   (`decision: :skipped`); and `FulfillCapabilityRequestExecutor` filters
   `action: "author_module"` gaps out of the plan with one line.
4. **The one purpose-built end-to-end orchestration exists but is unreachable.**
   `fulfill_capability_request` (compose → materialize → template → provision → smoke →
   ready, 10-state AASM, TOCTOU-safe frozen plan, blast-radius approval policy) has no
   seeded `Ai::Skill` row, is not router-auto-invokable, and has no operator approve
   endpoint — a composed request sits forever.
5. **Template validation never runs on any write path.** Conflict/footprint/closure
   analysis lives only in REST-only `compose_preview`; the sole enforcement of "don't save
   a conflicting template" is a disabled React button.

The highest-leverage fixes are small (§7): one `SIGNAL_BINDINGS` entry, three skill seed
rows + one approve endpoint, one changed filter line, and reusing the existing package
embedding pipeline for `NodeModule`/`NodeTemplate`.

---

## 2. End-to-end trace: "build a node for purpose X, nothing exists yet"

| # | Step | Status | Evidence |
|---|------|--------|----------|
| 1 | Agent receives "build a node that runs X" | PARTIAL | Only the Concierge chat surface accepts NL; static routing falls through to `provision_full_stack`, which requires an existing `template_id` (`plan_composer_service.rb:89-105`) |
| 2 | Guardrails point the agent at fleet tooling | MISSING | `Ai::Agent::BASE_GUARDRAILS` (`server/app/models/ai/agent.rb:39-48`) names only code/knowledge search tools; zero mentions of module/template/node/provision |
| 3 | Discover existing modules by purpose | MISSING | No embedding column on `NodeModule`; `system_list_modules` filters `variety` only (`system_fleet_tool.rb:1989`); marketplace is ILIKE-only REST |
| 4 | Discover existing templates by purpose | MISSING | `system_list_templates` declares `parameters: {}` (`system_fleet_tool.rb:514`) |
| 5 | Enumerate known capabilities | MISSING | Free-form strings; no registry/enum/validation anywhere (§5.4) |
| 6 | Rank existing modules semantically (fallback) | PARTIAL | `ModuleComposeExecutor` embeds candidates per call (nothing persisted); reachable only as a skill bound to two agents, not an MCP action |
| 7 | Discover candidate packages by purpose | **WORKS** | `system_discover_packages` → pgvector cosine + confidence buckets (§4) |
| 8 | Preview dependency closure | **WORKS** | `system_resolve_package_dependencies` (read-only) |
| 9 | Materialize package → module + dispatch build | **WORKS** | `system_create_module_from_package` → `PackageModuleMaterializer` (§3.3, with the build-planner caveat in §5.2) |
| 10 | No package covers X → author a module | MISSING | No from-scratch creation tool; `author_module` gaps filtered out (`fulfill_capability_request_executor.rb:106`, verified) |
| 11 | Unresolved capability becomes durable record | MISSING | Resolver/importer return-and-forget (`manifest_import_service.rb:677-691`); structurally unpersistable (`system_module_dependencies.dependency_id` NOT NULL) |
| 12 | Sensor → actionable signal | PARTIAL | `CapabilityGapSensor` fires; `DecisionEngine` has no binding for `system.capability_gap` (verified: zero hits) → `decision: :skipped` |
| 13 | Signal → `capability_gap` recommendation | MISSING | `Ai::ImprovementRecommendation` enum value exists; zero creation sites monorepo-wide |
| 14 | Recommendation → dev-loop authoring task | MISSING | `capability_gap` ∉ `CODE_QUALITY_TYPES` — excluded from the only promotion path (deliberate: proposed modules must pass the human R1/R2/R3 gate) |
| 15 | Create template + assign modules | **WORKS** | `system_create_template` + `system_assign_module_to_template` (validation caveats in §5.3) |
| 16 | Create node + provision instance | **WORKS** | `system_create_node`, `system_provision_instance`, pool tools |
| 17 | Verify the new module actually works | PARTIAL | `ModuleSmokeVerifyExecutor` exists but has no seeded `Ai::Skill` row; no manifest `verify:` block; nothing advances `promotion_state` past `built` |

Steps 7–9 and 15–16 are production-quality. Everything an agent needs *before* using them
(2–5) and everything that should happen *when the package path comes up empty* (10–14) is
missing or discarded.

---

## 3. Module lifecycle (discovery / design / creation / build)

### 3.1 Data model
`system_node_modules` (`server/db/schema.rb:9600-9650`), model
`extensions/system/server/app/models/system/node_module.rb`. Five base64-encoded rsync-glob
spec fields (`mask/file_spec/package_spec/dependency_spec/protected_spec`, `:43`) with
documented cross-neighbor semantics (`effective_mask` `:364-385`); `capabilities` JSONB
(GIN) denormalized from `dependencies.provides`; `manifest_yaml` as the only persisted
record of the `requires` side. `NodeModuleVersion` carries a manual promotion ladder
(`built → staging → blessed → live`, `node_module_version.rb:95-121`); `ModuleArtifact`
holds per-arch OCI ref/digest, fsverity root hash, cosign bundle, SBOM/provenance/VEX URIs.
`ModuleBuildBatch` is a real AASM machine (`module_build_batch.rb:46-96`).

### 3.2 Manifest schema
Authoritative JSON Schema `extensions/system/modules/.schema/module-manifest.schema.json`
(`additionalProperties: false`). Ruby parser `System::ManifestImportService` validates
schema_version/category/spec shapes/services/users/groups/sudoers and rejects `/home`
file_specs. **No `verify:` block exists** anywhere (schema, 27 shipped manifests, importer)
— a module cannot declare how to prove it works, and combined with the manual promotion
ladder there is no automated evidence path from artifact to `blessed`. (The settled
`verify:` probe design from the 2026-07-28 gap analysis remains unbuilt.)

### 3.3 Creation paths — four exist, one is agent-reachable
(a) **Human git authoring** of `modules/<slug>/` (canonical, no programmatic seam);
(b) **REST** create + `import_manifest`; (c) **CI publish** auto-create via
`ModulePublishTargetResolver`; (d) **MCP** `system_create_module_from_package` — the *only*
module-creating MCP action in the platform. It materializes the package closure with
baseline exclusion (base-os dedup → synthetic `requires base-os` edge), provenance links
(`PackageModuleLink` with persisted recommends/alternatives choices for deterministic
refresh), and build dispatch via Vault-signed `ModuleBuildBatch`.

### 3.4 Build/publish
CI workflow `build-platform-modules.yaml` is `workflow_dispatch`-only, one module per
dispatch, slug must exist as `modules/<slug>/manifest.yaml` (`:166-169`); mirrored in
`build-one-module.sh:149-150` and `module-forge-build.sh:281-282`;
`PlatformModuleManifestLoader` additionally skips non-git-tracked directories. Anything
non-apt requires a hand-written arm in the 80 KB, 13-arm `case "$MODULE"` `stage15.sh` —
the manifest is not a complete build description. Ingest is fail-closed on cosign verify
(Gitea path); signing is server-side via `ModuleSigningService` (env-only secrets, digest
mismatch refusal).

### 3.5 Capability resolution
Two `requires` syntaxes: documented `<owner>/<module>@<constraint>` and **undocumented**
`capability:<tag>[@constraint]` (used by 18 of 27 manifests, absent from schema + runbook).
`System::CapabilityResolver` resolves against the GIN-indexed `capabilities` column; both
resolver arms silently skip unresolvables (info-log + unpersisted
`{status: "unresolved"}`). `version_constraint` is stored but never re-checked after
import. `upsert_dependency!`'s capability-provenance write is a permanent no-op
(`if dep.respond_to?(:metadata=)` — the column doesn't exist).

---

## 4. Repository index / package search — the strongest subsystem

- **Catalog**: `System::PackageRepository` (apt/rpm/dnf, account/shared visibility with DB
  CHECK), `System::Package` (per (repo,name,arch,version); soft-obsoletion preserves
  provenance; purpose-bearing fields: summary, description, section, `provides` JSONB),
  `System::PackageModuleLink` provenance. Seeded shared repos: Debian stable + Ubuntu noble.
- **Sync**: `PackageRepositorySyncService` — advisory-locked, fingerprint fast-path,
  mass-obsoletion guard (>20% refusal), parser-version reparse, runs out-of-puma via
  `rails runner` spawn. Daily cron 05:00 UTC in the **extension's** worker tree
  (`extensions/system/worker/.../system_package_repository_sync_job.rb`) so core never
  names extension classes.
- **Embeddings**: `system_packages.embedding vector(1536)` + HNSW cosine index —
  **the only purpose-search embedding column in this domain**. Backfill job leases batches
  `FOR UPDATE SKIP LOCKED` with a deliberate operational-relevance lease order
  (`package.rb:53-78`). Coverage tooling: `rake system:packages:embedding_coverage` /
  `backfill_embeddings`.
- **Search**: one backbone (`System::PackageSearchService`) serving MCP + REST + UI.
  Modes lexical / semantic / hybrid (default), hybrid scored
  `0.45·trigram + 0.45·cosine + 0.10·prefix`. Semantic degrades to lexical and truthfully
  rewrites the reported mode. Structured filters incl. GIN-backed `provides` containment
  and cross-kind architecture expansion.
- **Purpose discovery**: `DiscoverPackagesByIntentExecutor` — pure cosine, deliberately no
  lexical fallback ("discovery's premise IS the semantic match"), per-result similarity +
  reason + confidence bucket (<0.30 high / <0.50 medium / else low).

**Caveats**: (1) purpose search only sees embedded rows — a repo synced before the
embedding pipeline existed, or whose backfill never ran, is silently invisible to
discovery; run `embedding_coverage` before trusting breadth. (2) Discovery ranks
*packages*, not solutions (returns `postgresql-15`, not "use TimescaleDB + closure").
(3) The hybrid trigram term is a Ruby-side 4-value step function
(1.0/0.85/0.65/0.3), not pg_trgm — intentional (scores semantic-only rows) but coarse.

**Unrelated subsystem note**: the parent repo's recent `fix(search)`/`revert(search)`
commits (`07122436c`, `ed081ce87`, `260621983`) touched the **code index**
(`code_discovery_tool.rb`), not package search. Full narrative in
`docs/operations/code-index-retrieval-quality.md`. Instructive contrast: the code index is
still fighting identifier-vocabulary mismatch (LLM summaries designed, unshipped); the
package catalog never had the problem because apt/rpm ship human-written prose — package
discovery is already in the state the code index is trying to reach.

---

## 5. Templates

### 5.1 Terminology
"Template" is overloaded three ways: `extensions/system/templates/` is **module-repo
scaffolding for humans** (no code reads it); `System::NodeTemplate` is the node
composition manifest (this section); mission templates are orchestration.

### 5.2 What exists
`NodeTemplate` (account-scoped name uniqueness, required `node_platform`, free-form
un-validated `config` jsonb read at provisioning for `init_script`/`boot_mode`/
`sdwan_network_id`/`legacy_rsa_keys`) + `TemplateModule` join (priority, enabled, config
deep-merge, `recommends_override` with a well-designed
replace/excluded/included algorithm). **No versioning, no history, no audit** of
composition changes. Rich REST surface (CRUD + `compose_preview` + `import`/`export`/
`clone`); a Visual Template Composer frontend that round-trips `compose_preview`;
five-template platform seed as a declarative Ruby spec. Apply path
(`TemplateApplyService` → `TemplateExpansionService` → `DependencyResolutionService` →
`NodeModuleAssignment`) is idempotent, never mutates operator-tuned assignments, and the
node-facing modules endpoint carries the fail-closed `resolution_complete?` 503 guard
(post-incident: the 2026-07-28 self-detach).

### 5.3 The holes
- **Validation is preview-only.** `TemplateComposerService#detect_conflicts`
  (dependency conflicts, instance-variety collisions, protected-spec overlaps) runs *only*
  in `compose_preview`; no write path (REST create/assign, MCP assign) calls it. The only
  enforcement is `TemplateComposerPage.tsx:130` — a disabled Save button, client-side.
  `assert_closure!` (agent path) checks resolvability + base-os presence only.
- **`compose_preview` has no MCP action** — the single most valuable design-time analysis
  is invisible to agents.
- **MCP write surface is severely truncated**: `system_create_template` declares
  `node_platform_id` optional while the model requires it (schema lie → opaque
  `RecordInvalid`); `system_update_template` accepts only name/description (config/
  enabled/public/admin_user unfixable post-create via MCP); TemplateModule's
  priority/enabled/config/recommends_override are unreachable from *every* write API
  (REST create takes only `node_module_id`); clone/import/export/apply are REST-only.
- **Governance is advisory**: `TemplateApprovalPolicy` (blast-radius classification —
  live-node templates require approval) is consulted by exactly two callers; a direct
  `system_assign_module_to_template` against a live template bypasses it and propagates
  fleet-wide on next apply. `TemplateClosureDriftSensor` exists as a backstop.
- **A designed-in trap for automated callers**: removing a module correctly means
  `enabled: false` (destroying the join nullifies `source_template_module_id` and
  permanently orphans derived assignments — documented in ARCHITECTURE.md:141-148), but
  no API can express `enabled: false`, and the destructive
  `system_unassign_module_from_template` is the only MCP-reachable removal.

### 5.4 Capability taxonomy
Free-form dotted strings (`runtime.go`, `database.postgres.primary`, `http.reverse-proxy`)
with **no registry, no enum, no validation, no schema pattern** — and only the `provides`
side is indexed. A typo'd `capability:runtime.nodejs` is indistinguishable from a genuine
gap at author time, import time, and sense time.

### 5.5 Prior art that already solves much of this
`FulfillCapabilityRequestExecutor` + `FulfillmentAdvanceOrchestrator` +
`ModuleComposeExecutor` already implement "design a template for an uncovered purpose":
semantic module ranking, gap detection, conflict check, frozen TOCTOU-safe plan,
`TemplateApprovalPolicy` consultation, creation **through the MCP tools**, closure
assertion, FK-ordered rollback. It is unreachable (trace step 1/10; §6) — the fix is
wiring, not building.

---

## 6. The triple discard — where "author a module" conclusions go to die

1. **Import time**: `ManifestImportService#resolve_capability_requirement` logs
   info "deferring" and returns `{status: "unresolved"}` — reaches an HTTP response body,
   never persisted (structurally unpersistable: `system_module_dependencies.dependency_id`
   NOT NULL).
2. **Sense time**: `CapabilityGapSensor` re-derives gaps each tick and emits
   `system.capability_gap` with correct fingerprints — but `DecisionEngine::SIGNAL_BINDINGS`
   has **no entry** for it (verified: zero `capability` hits in the file), so every gap
   terminates as `{decision: :skipped}`. Terminus: two `FleetEvent` rows + an ActionCable
   broadcast an operator would find only via a free-text kind filter. Also absent from
   `docs/FLEET_SENSORS.md`. The companion vessel — `Ai::ImprovementRecommendation`
   type `capability_gap` — has zero creation sites monorepo-wide.
3. **Compose time**: `ModuleComposeExecutor#gap_for_capability` correctly emits
   `action: "author_module"` when no package covers a capability — and
   `fulfill_capability_request_executor.rb:106`
   (`.select { |g| g[:action] == "materialize" }`, verified) throws it away before the
   orchestrator ever sees it. Provisioning proceeds on the partial closure; only the smoke
   step would notice.

Sensor advisoriness is deliberate (authoring must pass the human R1/R2/R3 sprawl gate) —
but "route to a human seat" and "terminate in `:skipped`" are different things. Today it
is the latter.

---

## 7. Ranked recommendations (report only — none implemented)

**P0 — small wiring, large leverage**
1. **Bind `system.capability_gap` in `DecisionEngine::SIGNAL_BINDINGS`** (route:
   notify/approval-request, not auto-remediate — preserves the R1/R2/R3 human gate).
   Converts the silently-dropped requirement into a surfaced, routable signal. This is
   the same "gap #1" identified in the 2026-07-28 autonomous-provisioning analysis, now
   half-built: sensor exists, binding doesn't.
2. **Seed the missing `Ai::Skill` rows** (`fulfill_capability_request`,
   `module_smoke_verify`, `boot_image_drift_rollout`) — they violate the extension's own
   convention ("new skills must have BOTH an executor AND an `Ai::Skill` record") and
   `SkillBindings.validate!` raises on exactly this condition. Add the missing
   `composed → approved` operator approve endpoint for `FulfillmentRequest` (the sweep
   deliberately excludes `composed`, so interactive requests hang forever).
3. **Stop discarding `author_module` gaps** at `fulfill_capability_request_executor.rb:106`
   — carry them into the frozen plan as a blocked/human-review step instead of silently
   provisioning a partial closure.

**P1 — close the discovery gap for modules/templates**
4. **Purpose search over modules and templates**: add embedding columns to
   `NodeModule`/`NodeTemplate` and reuse the package embedding pipeline verbatim
   (lease-ordered backfill, sync-triggered enqueue, coverage rake task) + add
   `system_discover_modules`/`system_search_templates` MCP actions. Interim cheap step:
   expose `ModuleComposeExecutor`'s semantic ranking as a plain MCP action and expose the
   `providing(capability)` scope over MCP.
5. **Expose `compose_preview` over MCP** and call conflict detection on the write paths
   (or at minimum return conflicts as warnings from create/assign).
6. **Point agents at the right tools**: fleet-aware discovery guidance in
   `BASE_GUARDRAILS`/concierge prompt (today's reuse-first text names only code/knowledge
   search tools), and add `module_compose`/`fulfill_capability_request` to the Concierge's
   seeded skill list (both already `binds_to` it).

**P2 — write-surface completeness and governance**
7. Fix the MCP schema lies and truncations: `node_platform_id` required in
   `system_create_template`; widen `system_update_template`; make TemplateModule
   priority/enabled/config/recommends_override settable (unblocks the correct
   "disable, don't destroy" removal); MCP clone/export/apply; register the two
   implemented-but-unrouted actions (`system_module_publish_target`,
   `system_module_publication_integrity`); make `system_validate_module_manifest`
   accept a bare manifest (today requires an existing `module_id`, contradicting the
   runbook's documented signature).
8. Enforce `TemplateApprovalPolicy` on mutation of live-node templates (today advisory,
   bypassable by direct assign), and add template versioning/history — agent-authored
   templates cannot be reviewed without a diff.
9. **Longer-term authoring seam**: a declarative build path (extend the manifest `build:`
   block) so new modules don't require hand-editing the 13-arm `stage15.sh`; an MCP
   file-commit capability (Gitea tool has none) or a proposal-based authoring flow that
   emits a reviewable branch. The R1/R2/R3 gate should be enforced *by* that automation
   (structured justification field), not bypassed.

---

## 8. Defects found along the way (queue-able, mostly independent of the above)

| Defect | Evidence |
|---|---|
| Writes to nonexistent columns on `Ai::ImprovementRecommendation` (`ai_agent_id`, `title`, `priority`, `description`, `metadata`) swallowed by `rescue StandardError` | `autonomy_controller.rb:132-140`, `self_learning_service.rb:141,210`, `recommendation_sensor.rb:63-64`; schema verified `server/db/schema.rb:2574-2593` has none of them |
| Modules created by `system_create_module_from_package` have blank `manifest_yaml` → invisible to `ModuleBuildPlannerService#known_module_names` even with `force_all` (they build only via the separate package-closure path; confusing dual-path) | `module_build_planner_service.rb:115,136-142` |
| `system.module_builds.dispatch` granted only to `system_worker` → `system_dispatch_module_build_batch` unreachable for any agent principal (deliberate blast-radius choice; document it on the tool) | `config/permissions.rb:587,927` |
| `upsert_dependency!` capability-provenance write is a permanent no-op (no `metadata` column) | `manifest_import_service.rb:722` |
| `version_constraint` stored but never enforced post-import — providers can drift out of constraint undetected | `manifest_import_service.rb:721`; resolver never reads it |
| `CapabilityResolver.resolve` returns `nil` for both "no provider" and "malformed constraint" — typos report as capability gaps, not manifest errors | `capability_resolver.rb:27` |
| `capability:` requires syntax used by 18/27 manifests but undocumented in schema + runbook | `module-manifest.schema.json`; `manifest_import_service.rb:678-691` |
| `LocalOciAdapter` fabricates digests and always passes `verify_signature` — dev/test green says nothing about supply-chain integrity | `module_oci_ingest_service.rb:435-451` |
| Extension code apparently absent from the MCP code index — `platform_code_semantic_search` returned zero lexical+vector candidates for `powernode-system` and `powernode/powernode-system` (caveat: repo-id naming unverified); if real, agents cannot code-search the extension at all | live MCP probe, 2026-08-03 |

**Doc staleness**: `FLEET_SENSORS.md` claims 22 files/21 sensors (actual 25/24) and omits
`CapabilityGapSensor`; `module-authoring.md` documents a `system_validate_module_manifest`
signature that doesn't match the implementation, a retired docker dry-run flow, and calls
`module_compose` keyword-based (it went semantic); no template-design runbook/tutorial
exists (13 tutorials, none cover authoring a `NodeTemplate`).

---

## 9. Cross-check: 2026-07-28 autonomous-provisioning gap analysis

| 2026-07-28 gap | State at this review |
|---|---|
| 1. Discovery produces nothing durable | Half-closed: `CapabilityGapSensor` built and firing; DecisionEngine binding + recommendation vessel never wired (§6) |
| 2. Agents can build but not author modules | Unchanged; now mapped precisely (§3.3, §7.9) |
| 3. MCP pointed at the wrong plane | Out of scope here (session-plane concern), still tracked in memory |
| 4. No post-compose capability verification | Unchanged: no manifest `verify:` block; `ModuleSmokeVerifyExecutor` exists but unseeded; nothing advances `promotion_state` past `built` |
| 5. Build throughput single queue | Not re-examined this review |
| 6. Live recomposition works | Confirmed closed previously; not re-examined |
