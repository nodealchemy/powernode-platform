# Skill Executor Development

> Status: active

How to author a system-extension skill executor — the unit of work that backs every entry in the `Ai::Skill` catalog. The post-2026-05 refactor consolidated every executor onto a shared `BaseSkillExecutor` parent class, a `binds_to` DSL, and a registry-driven binding seed; this guide reflects that pattern and is the canonical reference for new authors. The current roster is **64 executors across 7 categories** (`ls extensions/system/server/app/services/system/ai/skills/*_executor.rb` minus the base class; re-verified 2026-09-03) — see the auto-generated [`SKILL_EXECUTOR_CATALOG.md`](../../extensions/system/docs/SKILL_EXECUTOR_CATALOG.md) for the live inventory (do not hand-edit it).

## Table of Contents

- [What is a skill executor?](#what-is-a-skill-executor)
- [Architectural placement](#architectural-placement)
- [The `BaseSkillExecutor` contract](#the-baseskillexecutor-contract)
- [The `binds_to` pattern and SkillBindings registry](#the-binds_to-pattern-and-skillbindings-registry)
- [Worked example: scaffolding a new executor](#worked-example-scaffolding-a-new-executor)
- [`CrudFactory` pattern](#crudfactory-pattern)
- [Testing strategy](#testing-strategy)
- [Anti-patterns](#anti-patterns)
- [Observability hooks](#observability-hooks)
- [Verification commands](#verification-commands)
- [Related guides](#related-guides)

## What is a skill executor?

A **skill executor** encapsulates *how a skill runs*. An `Ai::Skill` row in the database — created by `system_skills_seed.rb` — is metadata only: name, description, category, system prompt, JSON-Schema inputs/outputs, an `executor_class` pointer in `metadata`. None of that knows how to do anything. The matching executor class at `extensions/system/server/app/services/system/ai/skills/<name>_executor.rb` is the code that actually executes the work when an agent or operator invokes the skill.

The distinction matters because the catalog row and the executor evolve at different cadences. Skill metadata is rewritten almost every release (descriptions tightened, system prompts tuned, tags re-organised). Executor code changes only when behaviour changes. Keeping them separate lets `platform.discover_skills` produce useful prompt-fragments without forcing a Ruby code change every time someone refines a description.

Skill executors live alongside — but are distinct from — **MCP tools** (see [`mcp-tool-development.md`](mcp-tool-development.md)). Tools are the registered actions a session can invoke directly (`system_list_nodes`, `system_create_architecture`, etc.) and have permission checks baked in. Executors are coarser-grained orchestrations that typically call one or more tools internally — a "cve_response" executor enumerates exposed modules across the fleet by calling `system_list_modules`, reads CVE rows via ActiveRecord, scores risk, and emits a plan. See [`concepts/agents-and-autonomy.md`](../concepts/agents-and-autonomy.md) for where executors sit in the broader agent execution flow.

## Architectural placement

| Concern | Location |
|---------|----------|
| Executor classes | `extensions/system/server/app/services/system/ai/skills/<name>_executor.rb` |
| Shared base | `extensions/system/server/app/services/system/ai/skills/base_skill_executor.rb` |
| CRUD parent | `extensions/system/server/app/services/system/ai/skills/crud_factory.rb` |
| Binding registry | `extensions/system/server/app/services/system/ai/skills/skill_bindings.rb` |
| Skill catalog seed | `extensions/system/server/db/seeds/system_skills_seed.rb` |
| Binding seed | `extensions/system/server/db/seeds/system_skill_bindings_seed.rb` |
| Specs | `extensions/system/server/spec/services/system/ai/skills/<name>_executor_spec.rb` |

Naming follows `<purpose>_executor.rb`. The class itself is `System::Ai::Skills::<Purpose>Executor`. The canonical skill slug `SkillBindings.derive_slug` produces from the class name is `"system-#{class_name.demodulize.underscore.sub(/_executor$/, '').dasherize}"`, so `CveResponseExecutor` becomes `system-cve-response`. Keep this alignment — the binding seed validates that every registered executor has a matching `Ai::Skill` row with the derived slug, and a mismatch fails the seed with an explicit list of orphans rather than producing partial state.

## The `BaseSkillExecutor` contract

Every executor inherits from `System::Ai::Skills::BaseSkillExecutor` (or `CrudFactory`, which itself inherits from it). The base class is small and stable; read `extensions/system/server/app/services/system/ai/skills/base_skill_executor.rb` for the canonical source. The contract has four moving parts.

### Required class-scope DSL

```ruby
class FooExecutor < BaseSkillExecutor
  skill_descriptor(
    name: "foo",
    description: "Short, action-oriented description for catalog UI",
    category: "fleet",           # internal subdomain — fleet|security|runtime|sdwan|documentation|topology
    inputs: {
      target_id: { type: "string",  required: true, description: "What is being acted on" },
      limit:     { type: "integer", required: false, default: 10 }
    },
    outputs: {
      result_id: :string,
      summary:   :object
    },
    requires_approval: false,    # default false; set true for mutating skills
    invocation_mode: "one_shot", # one_shot | workflow_step
    domain: "system",            # rarely overridden
    tags: %w[fleet diagnostics]
  )

  binds_to "Fleet Autonomy", "System Concierge"
  # ...
end
```

`skill_descriptor` freezes the hash and memoises it as `@descriptor`. Subclasses can read it back via `.descriptor`; the base class raises `NotImplementedError` if a subclass forgot to call it, which surfaces the bug at first reference instead of returning `nil` to a downstream caller. `requires_approval` is the static contract — set `true` here for skills that always touch infrastructure (architecture mutation, instance termination, rolling upgrades). Runtime conditions (e.g. "approve only if blast radius > 5% of fleet") belong inside the `success(...)` payload as a per-call `requires_approval` key, **not** the descriptor.

`binds_to` is a thin wrapper around `SkillBindings.register(self, agents: [...])`. Pass canonical agent names (`"Fleet Autonomy"`, `"CVE Responder"`, `"System Concierge"`, etc.) or short slugs from `SkillBindings::AGENT_ALIASES` (`"fleet_autonomy"`, `"cve_responder"`).

### Required instance method

```ruby
protected

def perform(target_id:, limit: 10)
  # Do the work. Return success(...) or failure(...).
  result = tool(::Ai::Tools::SystemFleetTool).execute(
    params: { action: "system_get_instance", instance_id: target_id }
  )
  return failure(result[:error]) unless result[:success]

  success(result_id: target_id, summary: { count: result[:data][:count] })
end
```

`perform` receives the same keyword args the caller passed to `execute(...)`. It must be `protected` — the public entry point is `execute`. Return `success(payload)` (becomes `{ success: true, data: payload }`) or `failure(msg)` (becomes `{ success: false, error: msg }`).

### Provided helpers

The base class provides everything subclasses need:

| Helper | What it does |
|--------|--------------|
| `success(payload)` | Canonical success shape — `{ success: true, data: payload }` |
| `failure(msg)` | Canonical failure shape — `{ success: false, error: msg }` |
| `tool(klass)` | Builds an `Ai::Tools::*Tool` instance with the executor's `account`, `agent`, `user` already passed in. Replaces the many sites that previously hand-constructed tool instances. |
| `validate_inputs!(inputs)` | Default required-input enforcement — any descriptor input with `required: true` must be non-nil in `inputs`, otherwise `ArgumentError`. Override for richer validation (enum membership, type coercion, mutual exclusion). |
| `audit_log_start(inputs)` | Tagged `Rails.logger.info` for entry — invoked automatically. |
| `audit_log_finish(result)` | Tagged `Rails.logger.info` for exit — invoked automatically. |
| `audit_log_error(exc)` | Tagged `Rails.logger.error` for uncaught exceptions — invoked automatically. |
| `@account`, `@agent`, `@user` | Attr-readers exposing the constructor args. |

### Lifecycle

`execute(**inputs)` runs:

1. `validate_inputs!(inputs)` — raises `ArgumentError` on missing required keys
2. `audit_log_start(inputs)`
3. `result = perform(**inputs)`
4. `audit_log_finish(result)`
5. `return result`

Any uncaught `StandardError` inside `perform` is wrapped:

```ruby
rescue StandardError => e
  audit_log_error(e)
  failure(e.message)
end
```

This is why subclasses must never wrap their own `perform` body in `rescue StandardError`. The base class already does it and produces the canonical failure shape; a subclass-level rescue swallows the exception before the logger sees it, and any contextual error message you tried to emit is lost.

## The `binds_to` pattern and SkillBindings registry

Before the refactor, every executor file ended with a hand-maintained `SkillBindings.register(self, agents: [...])` call, and the agent seeds maintained parallel hardcoded slug arrays. The two could drift — a skill could be registered to "Fleet Autonomy" in code while the seed bound it to "Runtime Manager" in the database, and nothing surfaced the conflict until someone investigated why an agent wouldn't invoke the skill.

The new pattern collapses both concerns into a single declaration at class scope:

```ruby
class DriftRemediateExecutor < BaseSkillExecutor
  skill_descriptor(...)
  binds_to "Fleet Autonomy"
  # ...
end
```

`binds_to` registers the executor with `System::Ai::Skills::SkillBindings`, an in-memory registry of `{ executor:, agents: [...] }` tuples. Because the registry is loaded at boot — the binding seed walks an executor glob to force-require every file before reading the registry — there is no chance of code/seed drift. The registry is the sole source of truth.

`system_skill_bindings_seed.rb` then:

1. Force-requires every `_executor.rb` so the registry is populated
2. Calls `SkillBindings.validate!`, which raises if any registered slug has no matching `Ai::Skill` row (catches "you added a binding but forgot the catalog row")
3. Walks `SkillBindings.discover`, which yields one `{ executor:, skill_slug:, agent_name: }` entry per (executor, agent) pair
4. For each tuple, `find_or_initialize_by(ai_agent_id:, ai_skill_id:)` and saves
5. Performs **drift correction**: any `Ai::AgentSkill` row for a system agent whose `(agent_id, skill_id)` pair isn't in the registry is destroyed

The drift correction step is what makes the registry truly authoritative. Removing a `binds_to` line and re-seeding will delete the corresponding `Ai::AgentSkill` row; renaming an agent in `binds_to` will rebind cleanly without leaving orphans.

Multiple agents are supported — `binds_to "Fleet Autonomy", "System Concierge"` produces two binding rows. Use aliases for readability: `binds_to :cve_responder` works because of the `AGENT_ALIASES` lookup table in `skill_bindings.rb`.

## Worked example: scaffolding a new executor

This walks end-to-end through adding a new skill called `detect_orphan_volumes` — a fictional executor that scans `System::Volume` rows for storage volumes whose owning NodeInstance has been deleted, returning candidates for reclamation. It binds to the **Storage Manager** (`binds_to "storage_manager"`, the `SkillBindings::AGENT_ALIASES` slug) because storage reclamation is a volume data-plane decision and belongs on that agent's approval chain (`Storage Manager Actions`) next to restore and snapshot delete — since HIER-P2DECL split Fleet Autonomy into the four operations managers, an executor binds to the agent whose policy set owns its domain, and Fleet Autonomy keeps only the fleet-wide lanes (certs, reboots, module promotion, rolling upgrades). One executor-specific ruling worth knowing: `attach_storage` binds to the **Capacity Manager**, not the Storage Manager, because it runs *during provisioning*.

### Step 1 — scaffold the executor file

Create `extensions/system/server/app/services/system/ai/skills/detect_orphan_volumes_executor.rb`:

```ruby
# frozen_string_literal: true

module System
  module Ai
    module Skills
      # Scans System::Volume rows for orphans (owning instance deleted or
      # in a terminal state). Returns reclamation candidates with an age
      # bucket so the operator can prioritise. Read-only — the actual
      # delete flows through `system_delete_volume`.
      class DetectOrphanVolumesExecutor < BaseSkillExecutor
        skill_descriptor(
          name: "detect_orphan_volumes",
          description: "List storage volumes whose owning instance is gone — reclamation candidates",
          category: "fleet",
          inputs: {
            min_age_hours: { type: "integer", required: false, default: 24,
                             description: "Only return volumes orphaned at least this long" }
          },
          outputs: {
            orphan_count: :integer,
            total_bytes:  :integer,
            volumes:      [ :object ]
          }
        )

        binds_to "storage_manager"

        protected

        def perform(min_age_hours: 24)
          cutoff = min_age_hours.to_i.hours.ago
          orphans = candidate_volumes(cutoff)

          success(
            orphan_count: orphans.size,
            total_bytes:  orphans.sum { |v| v.size_bytes.to_i },
            volumes:      orphans.map { |v| serialize(v) }
          )
        end

        private

        def candidate_volumes(cutoff)
          ::System::Volume
            .where(account: @account)
            .where("system_volumes.detached_at < ?", cutoff)
            .left_joins(:node_instance)
            .where(system_node_instances: { id: nil })
            .order(detached_at: :asc)
            .limit(100)
        end

        def serialize(volume)
          {
            id:           volume.id,
            name:         volume.name,
            size_bytes:   volume.size_bytes,
            detached_at:  volume.detached_at&.iso8601,
            backend:      volume.backend
          }
        end
      end
    end
  end
end
```

Because the file lives under `app/services/`, Rails autoloads it. No `require` is needed in the binding seed beyond the glob force-require it already performs.

### Step 2 — implement `perform`

Already done above. Note the shape: a single `perform` method using guard clauses where needed, a private helper or two for query construction, and a serializer that decides what the agent sees. Keep `perform` short — the descriptor is the contract, and the LLM consuming the result only needs the keys you declared in `outputs:`.

### Step 3 — declare `skill_descriptor` and `binds_to`

Already declared above. Verify two invariants before moving on:

- **Slug matches**: `DetectOrphanVolumesExecutor` → `system-detect-orphan-volumes` via the slug deriver. The catalog row in step 4 must use that exact slug.
- **Agent name matches**: `"storage_manager"` resolves through `SkillBindings::AGENT_ALIASES` to `"Storage Manager"`, exactly the `name` attribute on the seeded `Ai::Agent`. Typos here are caught by the binding seed (`unknown_agents` log warning + skip), but it's cheaper to fix them up front.

### Step 4 — seed the matching `Ai::Skill` row

Edit `extensions/system/server/db/seeds/system_skills_seed.rb` and append to `SKILLS_DATA`:

```ruby
{
  name: "Detect Orphan Volumes",
  slug: "system-detect-orphan-volumes",
  description: "List storage volumes whose owning instance is gone — reclamation candidates",
  category: "sre_observability",
  subdomain: "fleet",
  executor: "System::Ai::Skills::DetectOrphanVolumesExecutor",
  tags: %w[fleet storage cleanup],
  system_prompt: <<~PROMPT.strip
    Use this skill when an operator asks about reclaiming storage,
    finding unused volumes, or "what's costing me money in storage".
    Inputs: min_age_hours (default 24). Returns counts + a list with
    enough detail to call system_delete_volume on each.
  PROMPT
}
```

The `category:` here is the platform `Ai::Skill` enum value (one of `devops`, `security`, `sre_observability`, `release_management`, `documentation`, ...) — **not** the executor's internal `descriptor[:category]`. Read the docstring at the top of `system_skills_seed.rb` for the mapping table. Stash the tighter system subdomain in `subdomain:` so UI grouping still works.

### Step 5 — re-run seeds

```bash
cd server && bundle exec rails db:seed
```

Watch the output. You should see two relevant lines:

```
Seeding System extension AI skills catalog...
  ✅ Upserted 1 new skill row (system-detect-orphan-volumes)

Seeding agent ↔ skill bindings from SkillBindings registry...
    Registry has N (skill, agent) binding declarations
    ✅ Upserted 1 new/changed binding(s)
    • Storage Manager            → N+1 skill(s)
```

If you see `SkillBindings.validate! failed`, the slug in the catalog seed doesn't match the executor class name. Fix the seed and re-run.

### Step 6 — verify via MCP

From a session with `platform.*` access:

```
platform.discover_skills(query: "find unused storage volumes")
```

The new skill should appear with a high relevance score. Then:

```
platform.execute_agent(
  agent_id: "<storage-manager-id>",
  prompt: "Find me any orphaned volumes older than 48 hours"
)
```

The Storage Manager now has the skill bound, so the LLM can choose to invoke it.

## `CrudFactory` pattern

A subset of executors do nothing more than route to a single MCP tool action with a payload, wrap the response, and return. The architecture-create / architecture-update / architecture-delete trio is the canonical example. For these, inherit from `System::Ai::Skills::CrudFactory` instead of `BaseSkillExecutor`:

```ruby
class ArchitectureCreateExecutor < CrudFactory
  skill_descriptor(
    name: "architecture_create",
    description: "Create a custom (non-canonical) architecture",
    category: "fleet",
    inputs:  { name: { type: "string", required: true }, family: { type: "string", required: true } },
    outputs: { architecture: :object },
    requires_approval: true
  )
  binds_to "supply_chain_manager"

  protected

  def perform(name:, family:, **rest)
    crud_perform(resource: "architecture", operation: "create",
                 payload: { name: name, family: family, **rest })
  end
end
```

Adding a new CRUD destination is a two-step move:

1. Add the route to `CrudFactory::ROUTES`:
   ```ruby
   ROUTES = {
     [ "architecture", "create" ] => [ ::Ai::Tools::SystemArchitectureCatalogTool, "system_create_architecture" ],
     # ...add new tuple here...
     [ "volume", "create" ]       => [ ::Ai::Tools::SystemFleetTool, "system_create_volume" ]
   }.freeze
   ```
2. Write the thin subclass following the architecture example above.

`crud_perform` looks up `(resource, operation)` in `ROUTES`, calls `tool(tool_class).execute(params: payload.merge(action: action))`, and wraps the result. An unsupported route returns `failure("unsupported CrudFactory route: <resource>/<operation>")` rather than raising — the executor is well-behaved even with a bad payload.

Use `CrudFactory` only when the executor truly is a thin pass-through. The moment you find yourself adding business logic (validation that goes beyond `validate_inputs!`, cross-tool calls, conditional approvals), inherit from `BaseSkillExecutor` directly. `runbook_generate_executor.rb` is the canonical "rich" example — it calls a tool, then reads ActiveRecord, then assembles markdown, then optionally persists a `Page` row.

## Testing strategy

Each executor gets a spec at `extensions/system/server/spec/services/system/ai/skills/<name>_executor_spec.rb`. The pattern is:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe System::Ai::Skills::DetectOrphanVolumesExecutor do
  let(:account) { create(:account) }
  let(:exec)    { described_class.new(account: account) }

  describe ".descriptor" do
    it "advertises the static contract" do
      d = described_class.descriptor
      expect(d[:name]).to eq("detect_orphan_volumes")
      expect(d[:category]).to eq("fleet")
      expect(d[:requires_approval]).to be false
      expect(d.dig(:inputs, :min_age_hours, :required)).to be false
    end
  end

  describe "SkillBindings registration" do
    it "is bound to the Storage Manager" do
      reg = System::Ai::Skills::SkillBindings.all
        .find { |r| r[:executor] == described_class }
      expect(reg).not_to be_nil
      expect(reg[:agents]).to include("Storage Manager")
    end
  end

  describe "#execute" do
    context "with no orphans" do
      it "returns orphan_count=0" do
        result = exec.execute
        expect(result[:success]).to be true
        expect(result.dig(:data, :orphan_count)).to eq(0)
      end
    end

    context "with one orphan older than the cutoff" do
      before do
        create(:system_volume, account: account, detached_at: 30.hours.ago, node_instance: nil)
      end

      it "returns the orphan in the volumes list" do
        result = exec.execute(min_age_hours: 24)
        expect(result.dig(:data, :orphan_count)).to eq(1)
      end
    end
  end
end
```

Three things to always cover:

- **Descriptor shape** — at least `name`, `category`, `requires_approval`, and any required-input flags. Catches silent regressions in the catalog contract.
- **SkillBindings registration** — every executor must declare `binds_to` for it to matter at runtime. The spec is the only place this is checked at the class level, because the seed only validates that the registered slug has a matching `Ai::Skill` row (not the reverse).
- **Behavioural coverage** — at least a happy path, an empty/no-result path, and a failure-mode path. Don't test the base-class lifecycle (`success` / `failure` shape, exception trapping, audit logging) — that's `base_executor_spec.rb`'s job.

Where the executor calls a tool, prefer `instance_double` with `allow(::Ai::Tools::FooTool).to receive(:new).and_return(stub)`. This keeps specs hermetic and fast. The CRUD-factory specs (`crud_factory_spec.rb`) follow this pattern and are good models.

## Anti-patterns

Things the base class already does that subclasses must **not** redo:

- **Do not define `def initialize(account:, agent:, user:)`.** The base class owns the constructor and stores those instance variables. Defining your own initializer will at best duplicate code and at worst forget the `agent:` / `user:` keyword args, breaking tools that depend on them.
- **Do not define `def success` or `def failure`.** They exist on the base class with the canonical shape. Redefining them risks producing `{ status: "ok" }` instead of `{ success: true, data: ... }`, which the rest of the platform doesn't recognise.
- **Do not `rescue StandardError` in `perform`.** The base class wraps `execute` in `rescue StandardError → audit_log_error → failure(e.message)`. A subclass-level rescue swallows the exception before the logger sees it. If you need to rescue a *specific* known error class (e.g. `ActiveRecord::RecordNotFound`), that's fine — just don't rescue the world.
- **Do not put `requires_approval` in the top-level `success(...)` payload.** The descriptor is the static contract — if the skill always requires approval, set `requires_approval: true` in `skill_descriptor(...)`. If the requirement is dynamic (depends on blast radius, risk score, batch size), put a `requires_approval:` key **inside** the `success(...)` data hash, where `cve_response_executor.rb` puts it. The static descriptor controls catalog UI and policy routing; the dynamic flag is what individual responses negotiate.
- **Do not hand-construct tools.** Use `tool(::Ai::Tools::FooTool)` so the executor's `account` / `agent` / `user` flow through correctly. `Ai::Tools::FooTool.new(account: @account, ...)` works but duplicates the constructor signature, which has historically drifted.
- **Do not store mutable state on the instance.** Executors are constructed per-execute call (no caching, no pooling) but they're also short-lived objects with no concurrency guarantees. Cache nothing on `@`-prefixed ivars beyond what the base class already exposes (`@account`, `@agent`, `@user`).
- **Do not call `SkillBindings.register` directly from the executor file.** Use the `binds_to` DSL — it dedupes by class name (so dev-mode reloads don't multiply entries) and is the documented surface.

## Observability hooks

Beyond the automatic audit logging, two hooks are worth using when the executor's behaviour is interesting enough to influence future decisions:

### Emitting learnings

If `perform` discovers a pattern worth remembering across runs — e.g. "instances of platform X always orphan volumes when terminated abruptly" — emit a learning at the end of the run via the `Ai::Tools::LearningTool` helper:

```ruby
def perform(...)
  result = do_work
  ::Ai::CompoundLearning.create!(
    account_id: @account.id,
    category:   "discovery",
    title:      "Platform #{platform_name} orphans volumes on abrupt termination",
    content:    detailed_finding,
    tags:       %w[fleet storage platform-specific],
    status:     "active",
    importance_score: 0.6
  )
  success(result)
end
```

Use category `discovery` for one-off findings and `pattern` for repeatable patterns. The maintenance job will decay unused learnings automatically — see [`backend.md`](backend.md) for the lifecycle.

### Memory writes

For findings that should be available to other executors during the same fleet reconcile cycle, write to shared memory rather than the learning store:

```ruby
::Ai::SharedMemoryEntry.create!(
  account: @account,
  pool: ::Ai::SharedMemoryPool.find_by(name: "default"),
  key: "fleet.orphan_volumes.last_scan",
  value: { count: orphans.size, scanned_at: Time.current.iso8601 },
  ttl_seconds: 3_600
)
```

The TTL keeps it short-lived; the learning store is for durable knowledge.

## Verification commands

After landing a new executor:

```bash
# Run only the new spec
cd extensions/system/server && bundle exec rspec spec/services/system/ai/skills/<name>_executor_spec.rb

# Re-run the binding seed in isolation if you don't want to seed everything
cd server && bundle exec rails runner \
  "load Rails.root.join('../extensions/system/server/db/seeds/system_skill_bindings_seed.rb')"

# Verify the skill is discoverable
cd server && bundle exec rails runner \
  "puts Ai::Skill.find_by(slug: 'system-<name>')&.name"

# Verify the binding row exists
cd server && bundle exec rails runner \
  "puts Ai::AgentSkill.joins(:ai_agent, :ai_skill).where(ai_agents: { name: 'Storage Manager' }, ai_skills: { slug: 'system-<name>' }).count"
```

If the spec passes and the verification runners report `1`, you're done.

## Related guides

- [`mcp-tool-development.md`](mcp-tool-development.md) — adding the MCP tool action that an executor will typically call into
- [`concepts/mcp-and-tools.md`](../concepts/mcp-and-tools.md) — the full MCP surface and how executors fit
- [`concepts/agents-and-autonomy.md`](../concepts/agents-and-autonomy.md) — where executors sit in the agent execution flow
- [`backend.md`](backend.md) — Rails conventions, service boundaries, and the worker contract
- [`testing.md`](testing.md) — broader RSpec conventions for backend specs

_Last verified: 2026-06-03_
