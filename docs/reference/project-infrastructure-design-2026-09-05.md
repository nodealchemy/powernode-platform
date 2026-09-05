# Project infrastructure design: a project's own template and modules

Date: 2026-09-05. Status: design only. No code, no migrations, no live state was touched.
Every claim below is checked at a `file:line` in the working tree as of this date, or is
listed in §9 as unverified. Line numbers drift; the file and the identifier are the durable
part of each citation.

Scope, verbatim from the brief: what a project-scoped template is (clone, shared with overlay,
or generated); who owns a project's modules and whether assignment scope is sufficient
isolation; the lifecycle of active, paused and archived (what should happen versus what
currently would); the reach problem (seeds never re-run, no template reconciler); and the
declaration-versus-ownership question.

Constraints in force: extend existing machinery with a scope, never a parallel path; core never
references an extension class by name; no hardcoded hostnames, budgets or models; ops-hub
(VM 600) is never a test subject; no production tier. Four lanes are mid-flight (project
model, fleet services tree, generated artifacts, worker schedule), so nothing was edited.

---

## 0. Verdict

**Own the template, declare the modules.** Mint one derived `System::NodeTemplate` per project
(a lineage pointer to the base it was cloned from, a foreign key to the project) and keep
modules account-scoped and shared by default, with project ownership of a module as an explicit
opt-in that is guarded at assignment time. Template ownership is what lifecycle and blast-radius
reporting need something to act on. Module ownership by default would duplicate artifacts,
builds and versions per project, and would defeat the one property the supply chain gets
right today: a security publish reaches every node carrying the module.

**The single worst lifecycle transition** is `active → archived` while the project's template
still carries provisioned nodes. Nothing refuses it (the only guard that exists,
`restrict_with_error`, sits on template *destroy*, not on project archive), and afterwards
three fleet-wide loops keep acting on nodes nobody owns: template-closure convergence, publish
auto-promotion, and pool replenishment. Today "archived" is a label that nothing reads. §4.

**The isolation finding**: assignment scope is sufficient isolation *only if* a project-owned
module is assigned solely through the project's own templates, and nothing enforces that
invariant. Any operator or agent can join the module to another template or node, and the next
publish converges all of them, because `current_version_id` is one pointer per module per
account. §3.

---

## 1. What exists today

### 1.1 The project already has a template slot, and it is never written

- `server/app/models/ai/project.rb:22` header: the template reference is polymorphic
  (`template_type` + `template_id`), the class name is *data*, so core never names an
  extension class. `:109` `belongs_to :template, polymorphic: true, optional: true`.
  `:230-234` `template_ref` returns `{ type:, id: }` or nil.
- `:46` `STATUSES = %w[active paused archived]`; `:126-127` scopes `paused` / `archived`.
- `:111-114` `has_many :missions ... dependent: :nullify` with the comment "retiring the project
  ... must not erase" missions. This is a *destroy* behaviour; archiving does not trigger it.
- **No writer of `template_type` / `template_id` exists** in core or the system extension.
  Untruncated `command grep` over `server/app/models/ai/project.rb`,
  `server/app/services/ai/projects`, `server/app/services/ai/tools/project_tool.rb` and
  `extensions/system/server/app` finds only the two reads at `project.rb:231,233`. The
  `template_id` hits in `scale_project_executor.rb:108,211,229` are a caller-supplied parameter,
  not the project's pointer.
- `server/app/services/ai/tools/provisioning_tool.rb:669-675` `create_project_for!` writes
  `account`, `name`, `status: "active"`, `created_by` and nothing else; `:636-646` the
  infrastructure mission carries `project:`. The comment at `:663-668` makes the project
  deliberately best-effort and additive.
- `server/app/services/ai/tools/project_tool.rb:34` `ACTIONS = %w[project_list project_get
  project_status]`. Read-only.
- **No writer of `status` to `paused` or `archived` exists** in core or the system extension
  (untruncated grep; only the scopes at `:126-127` mention the values). No projects controller
  was found in core. The lifecycle states exist as vocabulary only.

### 1.2 The template machinery is account-scoped and node-frozen

- `extensions/system/server/app/models/system/node_template.rb:21-27`: `has_many :nodes ...
  dependent: :restrict_with_error`, `has_many :template_modules, dependent: :destroy`,
  `node_modules` through the join. `:30` name unique per account. Schema
  `system_node_templates` (`db/schema.rb` ~9800-9810): `config`, `enabled`, `public`,
  `node_platform_id`. **No lineage, canonical, source-key or project column.**
- `system_template_modules` (~11240-11246) is `(node_template_id, node_module_id, priority,
  enabled, config)`. No project dimension.
- `system_node_module_assignments` (~9572-9580) is node-scoped: `node_id`, `node_module_id`,
  `priority`, `enabled`, `auto_resolved`, `source_template_module_id`. Assignments are
  materialised once at provision and are not a live view of the template (memory
  `node-assignments-frozen-at-provision`); `template_apply_service.rb:9-19,44-88` is the
  additive, idempotent way to bring a node up to its template, and `purge_stale` removes only
  rows that carry a `source_template_module_id`.
- `TemplateExpansionService` (`template_expansion_service.rb:59`) honours
  `TemplateModule.enabled` (`template_module.rb:20`). **`NodeTemplate.enabled` has no consumer**
  other than the serializer (`node_template_serializer.rb:14`), the exporter
  (`template_exporter.rb:52`) and the update-verb description (`system_fleet_tool.rb:1128`).
  A disabled template is still provisionable. Finding, §4.3.
- Cloning, import and export exist: `template_clone_service.rb` (same-account deep clone),
  `template_importer.rb` / `template_exporter.rb` (JSON bundle keyed by module name and
  variety), `template_composer_service.rb`.
- `system_fleet_tool.rb:1511` `system_assign_module_to_template` refuses composition conflicts
  and, when the template already has live nodes, reports `blast_radius` and records a
  `system.template_mutation` event. `:2149` `system_unassign_module_from_template` warns that
  destroying a join "nullifies `source_template_module_id` on derived assignments and orphans
  them" and recommends `enabled=false` instead.
- `TemplateClosureDriftSensor` (`template_closure_drift_sensor.rb:1-18`) measures nodes whose
  assignments lag their template; `apply_template_closure_drift`
  (`decision_engine.rb:2775-2800`) converges them, fingerprint self-clearing.

### 1.3 Module ownership is the account, and promotion is one pointer

- `node_module.rb:8` `VARIETIES = %w[config instance subscription]`; `:69-85` `parent_module`
  and `dependants`; `:163` `scope :enabled`; `:165` `public_modules`; `:187` `for_node` via
  assignments. Schema `system_node_modules` (~9676-9719): `account_id NOT NULL`, `auto_promote`
  default true, `current_version_id`, `node_id`, `node_instance_id`, `parent_module_id`,
  `public`, `lock_spec`, `consent_budget_per_day`. **No project column.**
- `module_publication_processor.rb:95-125` publish auto-promotes unless `auto_promote?` is
  false (`:339-345`, `node_module.auto_promote != false`), an artifact floor, core drift or a
  missing signature withholds it, emitting `system.module_promotion_withheld`.
  `auto_promote: false` is settable through `system_update_module`.
- `rolling_module_upgrade_executor.rb:30-33,82,87`: "every instance carrying the module
  converges" on `current_version_id`. Fleet-atomic by construction.
- `system_fleet_tool.rb:2273` `system_rollback_module_version` is the forward-repoint.
- `node_api/modules_controller.rb:15` serves the node its desired module list as
  `node_modules.enabled` where `node_modules` is `through: :node_module_assignments`
  (`node.rb:66`) and `.enabled` is the **module-level** scope (`node_module.rb:163`). The
  comment at `:17-27` records why this matters: the agent treats a module missing from that
  list as "unassigned" and detaches it; on 2026-07-28 ops-hub detached its own rails, traefik
  and sidekiq that way. Setting `enabled=false` on a *shared* module detaches it on every
  node in the account.

### 1.4 The precedent to copy is TeamProvisioner

- `server/app/services/ai/projects/team_provisioner.rb:7-12`: "REUSE, NOT A SECOND PATH";
  seats are clones minted by `AccountPrincipalResolver` with a `canonical_clone` lineage edge.
  `:99` `narrow_delegate_types`, `:112` `narrow_delegatable_actions` are the narrowing guards;
  `:132` `provision!`; `:204-205` the canonical is found by slug.
- `server/app/services/ai/teams/canonical_team_reconciler.rb:1-40`: three views, `drift`
  is read-only.
- The extension side still identifies "the project" as an `Ai::Mission`:
  `scale_project_executor.rb:6,102-103` ("Ai::Mission id (the provisioning project being
  scaled)"); `provision_full_stack_executor.rb:37,193,210` takes a `template_id` from the
  caller. No `project_id` or `mission_id` column exists on `system_nodes`,
  `system_node_instances` or `system_instance_pools`. Nodes are tied to a project only
  transitively, through a mission's recorded `node_instance_ids` outputs
  (`scale_project_executor.rb:30-31,133-134`).

### 1.5 Seeding and repair

- `server/db/seeds/powernode_platform_templates.rb:1-28` seeds five platform templates with
  `find_or_initialize_by(account, name)`, rebuilds `TemplateModule` rows and removes stale
  ones (`~:173`), and is explicitly runner-invokable (`~:194`).
- `extensions/system/server/app/services/system/account_bootstrap_service.rb:8-17` is the
  per-account catalog bootstrap (platforms, categories, modules, templates), idempotent by
  `find_or_create_by!`, "re-runnable manually: `System::AccountBootstrapService.call(account)`"
  (`:17`), called from `server/app/models/account.rb:488`. `:64` `seed_templates_for(account)`
  is the template step on its own; `:312` `find_or_create_by!(account:, name:)` for templates;
  `:332-337` `TemplateModule` rows are `find_or_initialize_by` and stale rows are dropped.
  So it reconciles *joins* for templates it knows, but a `find_or_create_by!` never updates an
  existing template's own fields.
- Memory `seeds-never-rerun-after-first-boot`: nothing re-runs a seed after first boot; an
  install whose first boot predates a seed file never gets its rows.
- **No `TemplateReconciler` class exists** (untruncated grep of both trees). The only
  reconciler in the codebase, `CanonicalTeamReconciler`, is for teams and reads the DB it
  would be diagnosing.

---

## 2. What a project-scoped template is

Three candidate shapes, judged against the machinery in §1.2.

| Shape | What it is | What it reuses | What it costs | Verdict |
|---|---|---|---|---|
| **Clone** | A real `NodeTemplate` row per project, deep-cloned from a base | Everything: provision, drift sensor, export, blast radius, `restrict_with_error` all work unchanged (`TemplateCloneService`) | Duplicates `TemplateModule` *join rows*; base-template membership changes do not propagate | **Chosen**, with a lineage pointer so the non-propagation becomes measurable drift |
| **Shared with overlay** | The project references a shared base and adds its own joins on top | Expansion already computes a closure (`template_expansion_service.rb`) | `TemplateModule` has no project dimension: needs a new join table or a `parent_template_id` and every consumer (clone, import, export, drift sensor, composer, blast radius) must learn to walk the parent | A second expansion path in disguise; rejected |
| **Generated** | Composed at provision time from project config (`TemplateComposerService`) | Composer exists | No durable row: nothing to list, nothing for `TemplateClosureDriftSensor` to compare against, no `restrict_with_error` on a thing that does not exist | Rejected |

**Definition.** A project-scoped template is an ordinary `System::NodeTemplate` row that
(a) carries `ai_project_id` (an extension-to-core foreign key, which the purity rule permits:
extensions depend on core, never the reverse) and (b) carries `source_template_id`, the base it
was cloned from. The project points back through the polymorphic slot that already exists
(`project.rb:109`), written for the first time.

**What is duplicated, and why that is acceptable.** Only join rows in `system_template_modules`.
Not modules, not versions, not artifacts, not builds. A clone must never clone a module. This
is the same trade `TeamProvisioner` already makes: clone the *seat* (a row with a lineage edge),
never the canonical's definition.

**What the lineage pointer buys.** Base-template drift becomes a sensor question ("base closure
minus derived closure") instead of a silent divergence. That sensor is the same one §5 needs for
canonical templates; it is designed once.

**Minting.** A `ProjectTemplateProvisioner` in the system extension, shaped exactly like
`TeamProvisioner` (`:132 provision!`, canonical found by slug at `:204-205`): find the base by
name in the account, `TemplateCloneService` it, stamp lineage and owner, write
`project.update!(template: clone)`. Idempotent: a project that already has a derived template
gets it back, never a second one. The narrowing guards of `TeamProvisioner` (`:99,:112`) have
an analogue here: the clone may *remove* joins from the base closure (narrow) or add
project-owned modules, but may not add a module the base's platform conflicts with, which is
already what `system_assign_module_to_template` refuses (`system_fleet_tool.rb:1511`).

---

## 3. Who owns a project's modules, and whether assignment scope isolates

### 3.1 The reach of a publish

A `NodeModule` is account-scoped with one `current_version_id` (§1.3). Publish auto-promotes
(`module_publication_processor.rb:95-125`); the rolling executor converges "every instance
carrying the module" (`rolling_module_upgrade_executor.rb:82`). The set of instances a publish
reaches is therefore the set of nodes with an *assignment* to the module, however that
assignment got there: from the project's template via `TemplateApplyService`, from another
template that also joined the module, or directly on a node. The template a node was provisioned
from is not consulted at promotion time.

**Consequence.** Assignment scope isolates a project-owned module's version changes to project
nodes *if and only if* every assignment of that module descends from the project's own
templates. Nothing enforces this:

- `system_assign_module_to_template` (`system_fleet_tool.rb:1511`) checks composition
  conflicts and reports blast radius; it does not check who owns the module or the template.
- Direct node assignments (`system_node_module_assignments.node_id`) have no template at all.
- `NodeModule.public` (`node_module.rb:165 public_modules`) widens visibility further; its
  cross-account semantics are unverified (§9).

So: **a project module version change can reach non-project nodes** the moment someone joins
that module elsewhere, and the reverse also holds: a project template that carries a *shared*
module (the platform base, traefik, the agent's own `powernode-system-base`) receives every
publish of that module, which is correct and must stay so.

### 3.2 The disable lever is fleet-wide too

`enabled=false` on a module removes it from the desired-state list of every node in the
account (`modules_controller.rb:15`, module-level scope) and the agent detaches it
(`:17-27`). Any lifecycle that "retires a project's modules" by disabling them must first prove
the module is assigned only to project nodes, or it repeats the 2026-07-28 self-detach on
whichever non-project node shares it.

### 3.3 Design: ownership is a column, isolation is a guard

- `system_node_modules.ai_project_id`, nullable. NULL means account-shared (today's meaning
  for every existing row). Non-NULL means project-owned.
- **Guard A (assignment):** `system_assign_module_to_template`, `TemplateApplyService` and
  the direct node-assignment verb refuse to join a project-owned module to a template or node
  that is not owned by the same project. This is the invariant that makes assignment scope
  sufficient. It is a narrowing guard in the `TeamProvisioner:99,112` sense: it removes
  options, it adds no path.
- **Guard B (retire):** `enabled=false` on a project-owned module is refused while any
  assignment exists outside the project; with Guard A in place this cannot happen for rows
  created after the guard, but pre-existing rows must be checked, not assumed.
- **Reporting, not a new path:** the publish event already exists
  (`system.module_promotion_withheld` and its promoted sibling). Extend the promoted event's
  payload with reach grouped by project: "reaches N nodes in projects A, B and M unowned
  nodes". `system_assign_module_to_template` already computes `provisioned_node_count` for
  `blast_radius` (`:1511`); the same count, grouped, is the whole change.
- **Holdback is existing machinery:** `auto_promote: false` via `system_update_module`, the
  withheld event, and `system_rollback_module_version` (`:2273`) as the forward-repoint. A
  project's default for `auto_promote` on modules it owns lives in `project.configuration`
  (jsonb, `ai_projects` schema), never a constant. A project that wants canary-by-default sets
  it there.
- **Shared modules stay shared.** The base image, the agent, ingress, and anything a platform
  template ships remain `ai_project_id IS NULL`. A project never gets a private copy of the
  agent; the security property of §3.1 is worth more than per-project pinning. A project that
  needs to pin a shared module's version is a `lock_spec` question (column exists,
  `~9676-9719`), which is unverified in behaviour (§9) and out of scope here.

---

## 4. Lifecycle: active, paused, archived

### 4.1 What happens today

Nothing. The status column can be set (no verb does; a console or direct update would) and no
code path reads it except the two scopes. Concretely, after `status = 'archived'`:

| Loop | Reads project status? | What it does to an archived project's nodes |
|---|---|---|
| Provision (`provision_full_stack_executor.rb:37,193,210`) | No, takes `template_id` from the caller | Provisions more |
| Scale (`scale_project_executor.rb:102-103`) | No, takes a mission id | Scales |
| Template-closure converge (`decision_engine.rb:2775-2800`) | No | Keeps nodes converged to the template |
| Publish auto-promote (`module_publication_processor.rb:95-125`) | No | Upgrades every assigned node |
| Pool replenish (`lifecycle_class` ephemeral/spot, `mark_pool_ready!`) | No | Refills |
| Missions | Only on project *destroy* (`project.rb:112-114`) | Unchanged |

A `NodeTemplate` with nodes cannot be destroyed (`restrict_with_error`, `:21-27`), which is the
one and only safety that survives the transition, and it protects the template, not the
project.

### 4.2 What should happen

Every transition is a `ProjectTool` verb (`project_tool.rb` is the existing tool; it gains
`project_pause`, `project_resume`, `project_archive`), each `mutating: true` and each declaring
what it holds. The holds are read by the loops above through the derived template
(`node_template.ai_project_id → project.status`), which is the one join that reaches all of
them. No loop learns about projects directly; each asks its template "may I act?".

**active → paused: freeze desired state, touch no running instance.**

- Provision and scale refuse when the target template's project is paused. They already have
  the template id in hand.
- Template-closure converge declines (the sensor still *measures*, so the operator sees drift
  accumulating; only the actuator holds). This is the `notify`-lane discipline already in use.
- Publishes of project-owned modules are withheld: `auto_promote?` returns false while the
  owning project is paused, emitting the existing `system.module_promotion_withheld` with
  reason `project_paused`. Shared modules are unaffected (they are not the project's to hold).
- Pools owned by the project (through the template) stop replenishing; desired stays, actual
  drains only by attrition. Stopping running instances is a capacity decision, offered as a
  separate consent-gated actuator, never implied by "pause".
- Health, heartbeats, sensors: unchanged. Paused is not silent.

**paused → active: release holds, surface what was withheld.**

- One `TemplateApplyService` pass per node (additive, idempotent) picks up template changes made
  while paused.
- Withheld promotions are *not* silently released; each is surfaced as a pending decision with
  the reach report from §3.3. Releasing a queue of promotions at once is exactly the batch the
  bulk-operation rule forbids without a count and a confirmation.

**active or paused → archived: retire, keep history.** Ordered, because §3.2 makes the order
load-bearing:

1. Refuse while the derived template has provisioned nodes, mirroring `restrict_with_error`,
   and name them. Offer the decommission actuator (consent-gated, destructive) as the next
   step. Archive never decommissions implicitly.
2. Once no nodes remain: release pooled instances the project holds, then mark the derived
   template non-provisionable (see §4.3), then `enabled=false` project-owned modules (safe now,
   because Guard A means no non-project node carries them, and step 1 means no project node
   does either).
3. Keep every row. Missions stay attached (nullify is a destroy behaviour, `:112-114`, and
   archive is not destroy). Template, joins, modules, versions and events remain for audit and
   for `paused`-style resurrection if the operator un-archives, which is a fourth transition
   that should exist and should require the provisioner to re-validate lineage drift first.

**archived → active** (un-archive): re-run the provisioner idempotently, report base-template
drift (§5) before anything provisions, re-enable modules. Not a hot path; must exist so that
archive is not accidentally terminal.

### 4.3 `NodeTemplate.enabled` must mean something or go

Today it is serialized and exported and settable, and nothing reads it (§1.2). Two acceptable
outcomes, pick one in the increment: give it teeth (provision and scale refuse a disabled
template, the drift actuator declines for it) so that archive can use it in step 2; or remove it
from the update verb's advertised fields (`system_fleet_tool.rb:1128`) so no operator believes
they have a hold they do not. Leaving a control that reads as a hold but holds nothing is the
`absence-of-a-refusal-is-not-a-passed-gate` class of defect.

### 4.4 The worst transition, stated once

`active → archived` with live nodes. It succeeds, it changes nothing that any loop reads, and
from then on the project's nodes are converged, upgraded and replenished by fleet-wide loops
under no owner, while the natural cleanup move (disable the project's modules) can detach shared
modules from non-project nodes. The fix is step 1 above: refuse, name the nodes, offer
decommission.

---

## 5. Reach and repair

### 5.1 The hole

Canonical templates are created by two one-shot mechanisms: the platform seed
(`powernode_platform_templates.rb`, runs on `db:seed`) and the per-account bootstrap
(`AccountBootstrapService`, runs when an account is created, `account.rb:488`). Neither re-runs
on its own after first boot (memory `seeds-never-rerun-after-first-boot`), so an install whose
first boot predates either file has accounts with no canonical templates, and there is no sensor
that would notice. `CanonicalTeamReconciler` has the same shape for teams and shares the same
hole: it reads the database it is diagnosing, so an account that never got its canonical rows
reports nothing to reconcile.

### 5.2 What exists as a repair path

- Manual: `System::AccountBootstrapService.call(account)` (`:17`, documented as re-runnable),
  or its template step alone, `seed_templates_for(account)` (`:64`). Creates what is missing,
  reconciles `TemplateModule` joins for templates it knows (`:332-337`), never rewrites an
  existing template's own fields (`find_or_create_by!`, `:312`).
- Manual: the platform seed via runner (`~:194`), which does rebuild joins with stale removal
  (`~:173`) and does `find_or_initialize_by`, so it will update an existing row's fields.
- Both are operator-invoked, un-observed, and not offered by anything. Neither is a
  reconciler; each is a bootstrap that happens to be idempotent.

### 5.3 What should exist, and what must not

- **A catalog-presence sensor** (`PlatformCatalogDriftSensor`, one more entry in
  `FleetAutonomyService::SENSORS`) that asks, per account: are the canonical templates and
  their joins present as the bootstrap would create them? Its oracle is the bootstrap's own
  spec, not the DB. Its actuator is `AccountBootstrapService.seed_templates_for(account)`.
  Reuse, not a path.
- **A lineage-drift sensor** for derived templates (§2): base closure minus derived closure,
  per project template, read-only first exactly as `CanonicalTeamReconciler.drift` is. Its
  actuator (`apply_template_lineage_drift`) is additive like `TemplateApplyService`, behind
  consent, and never removes a project's narrowing.
- **What must not be built:** a live "template reconciler" that rewrites operator-edited
  templates to match the seed. The seed's `find_or_initialize_by` already does that when
  invoked, and it would silently undo a project's narrowing. The distinction needs a marker,
  and `NodeTemplate` has none (§1.2). One column serves both uses: `source_template_id` NULL
  plus a `managed_by` value of `platform` marks a canonical; `source_template_id` set marks a
  derived template. The sensor may only *report* on the first and only *add* to the second.

---

## 6. Declaration versus ownership

**Declaration** means the project points at things it uses (`template_ref` at a shared
template; modules shared). **Ownership** means rows carry the project's id and guards act on it.

| | Declaration only | Ownership of everything | Recommended: own the template, declare the modules |
|---|---|---|---|
| Schema | none (write `template_ref` today) | FK on templates, modules, and by implication versions and builds | FK on templates; nullable FK on modules for the opt-in |
| Isolation | none: a shared template's mutation (`:1511`) reaches every project on it | by construction | by construction for templates; by Guard A for the modules a project chooses to own |
| Lifecycle can act? | no: nothing is "the project's" | yes | yes, through the template |
| Duplication | none | modules, versions, artifacts, builds per project | join rows only |
| Security publish reaches all nodes? | yes | **no**, each project pins its own copy | yes for shared modules |
| Reconciler needed? | no (nothing to drift) | yes, per project, for everything | yes, once, shared with the canonical-template case |
| Cost | a dozen lines | a new supply chain per project | two columns, one provisioner, two guards, one sensor pair |

**What the recommendation costs, honestly.** Two migrations on extension tables; a provisioner
that is a near-copy of `TeamProvisioner`; guards in three write sites; a sensor and actuator
pair that nobody has built for canonical templates either, so it is new work, not extension of
existing work; and the four lifecycle verbs. The `Ai::Mission`-as-project identification in the
extension executors (`scale_project_executor.rb:102-103`) does not need to change for any of
this, because the template, not the mission, is the join point. It should still change
eventually, and that belongs to the lane that owns the project model.

---

## 7. Increments

Each is provable on its own and none requires the next.

| # | Change | Proof | Risk |
|---|---|---|---|
| I1 | Write `project.template_ref` at provision (`provisioning_tool.rb` and `provision_full_stack_executor.rb`) and show it in `project_get`. No schema. | `project_get` returns a non-nil `template` for a newly provisioned project | none; the column exists and is optional |
| I2 | `source_template_id`, `managed_by`, `ai_project_id` on `system_node_templates`; nullable `ai_project_id` on `system_node_modules`; `ProjectTemplateProvisioner` mirroring `TeamProvisioner` | provisioning a project mints exactly one derived template, idempotently; `system_get_template` shows lineage and owner | additive columns only |
| I3 | Guard A and Guard B; publish event reach grouped by project | joining a project-owned module to a foreign template is refused with the owner named; a publish event lists per-project node counts | refuses a write that was previously silent |
| I4 | `project_pause` / `project_resume` / `project_archive` / un-archive on `ProjectTool`; provision, scale, converge and publish consult the template's project status; archive refuses while nodes exist and offers decommission | pause a project, publish one of its modules, observe `module_promotion_withheld` with reason `project_paused`; attempt archive with nodes, observe refusal naming them | the holds are refusals; nothing is stopped or deleted |
| I5 | `PlatformCatalogDriftSensor` + bootstrap actuator; lineage-drift sensor read-only, then additive actuator behind consent | an account with a deleted canonical template is reported and repaired; a base-template join added after cloning is reported as drift on the derived template | actuators are additive; the sensor pair is measure-first |
| I6 | Give `NodeTemplate.enabled` teeth or drop it from the update verb | provisioning a disabled template is refused, or the field disappears from the verb description and the serializer | one-line either way; decide before I4 uses it |

Order: I1 today (it is a dozen lines and removes a false "no template" from every project
read); I2 and I3 together; I6 before I4; I5 last because it is the only genuinely new
machinery.

---

## 8. What this design refuses to do

- No parallel expansion path (overlay), no generated templates, no per-project module copies.
- No hardcoded template names: the base a project clones from is chosen by the caller (or a
  `project.configuration` key), never a constant in the provisioner.
- No implicit destruction: archive never decommissions; pause never stops an instance.
- No self-test on ops-hub: the derived template for the control plane's own project, if one
  is ever minted, is fenced by `SelfManagementFence` like every other actuator.
- No user interface.

---

## 9. What could not be verified, and why

- **Live data.** How many `Ai::Project` rows exist, whether any has `template_type` set,
  whether any account lacks canonical templates, and how many `NodeTemplate` rows would need a
  `managed_by` backfill. No database was read: design only, and read access to the control
  plane's database runs through a break-glass path that a lane must not arm on its own.
- **Private extensions.** The untruncated `command grep` sweeps covered `server/` and
  `extensions/system/`. `extensions/private/*` was not swept; a private extension could carry a
  project status writer or a template pointer writer this document says does not exist.
- **The project-model lane.** That lane is mid-flight. Anything it has added since these reads
  (a `pause!`, a controller, a writer of `template_ref`) supersedes §1.1 and §4.1.
- **`NodeModule.public`** (`node_module.rb:165`): whether it grants cross-account visibility, and
  therefore whether a public project-owned module escapes Guard A. Not read.
- **`lock_spec`** on `system_node_modules`: whether it pins a version per node or per module,
  and whether it interacts with `auto_promote`. Not read; §3.3 defers it.
- **`copy_path`** (`node_module.rb:66`): what it copies and whether cloning a template touches
  it. No comment at the site.
- **`TemplateCloneService` field coverage**: it was read as a same-account deep clone; whether
  it copies `config` and `node_platform_id` byte-for-byte was not confirmed line by line.
- **`account.rb:488`** invokes `AccountBootstrapService.call(self)`; the callback that wraps it
  (after-create or otherwise) was not read, so "runs when an account is created" is inferred
  from the service header (`:8`), not from the callback.
- **Line numbers in the seed** (`~:173`, `~:194`) and in `db/schema.rb` are from earlier reads
  in this session and are marked approximate.
