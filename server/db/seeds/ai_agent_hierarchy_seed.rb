# frozen_string_literal: true

# Core agent hierarchy (HIER-P1, extended by HIER-P2B-ENG) — the GLOBAL
# platform agents as seeded lineage: one active Ai::AgentLineage edge each
# (spawn_reason "seed") and one Ai::DelegationPolicy row, written through
# Ai::Agents::HierarchyWriter — the same seam every runtime creation path
# uses, so the Autonomy page's lineage forest and the delegation checks
# describe one structure.
#
# TWO CORE ROOTS, one operator ruling. System Concierge (an EXTENSION agent)
# coordinates both hierarchies, but core never reaches for an extension agent,
# so core seeds two roots and the system extension's hierarchy seed attaches
# BOTH under System Concierge when it is present:
#
#   Powernode Assistant (core concierge)     — the fundamental core forest
#   Platform Architect  (Engineering manager) — the Engineering hierarchy:
#     Platform Developer, Release Manager, Documentation Specialist (new core
#     canonicals, ai_engineering_agents_seed.rb) and the six existing
#     canonicals that build the platform rather than run it — Research
#     Analyst, Strategic Planner, PRD Generator, LLM Judge, System Quality
#     Assurance, Knowledge Graph Curator — re-parented here from Powernode
#     Assistant (HierarchyWriter#attach! closes the old edge: one active
#     parent per child). Phase 4 seeds the "Platform Engineering"
#     Ai::TeamTemplate on top of these edges.
#
# Runs LAST in the baseline agent block (db/seeds.rb) so every canonical the
# agent seeds create already exists. Idempotent: a re-run changes nothing.
#
# The children are listed by slug, and spec/db/seeds/ai_agent_hierarchy_seed_spec.rb
# pins the lists against the seed files it loads: every global agent those
# files create, other than the two roots, must carry exactly one edge, so a
# new canonical added to one of THOSE files fails the spec instead of shipping
# as a "standalone" node. A canonical introduced by a NEW seed file is only
# covered once that file is added to the spec's list too.
#
# Delegation (operator rulings 2026-09-03):
#   * core-forest children: single-purpose, `conservative`, max_depth 1, no
#     delegate types and no delegatable actions (Ai::DelegationPolicy
#     #allows_delegate_type? treats an EMPTY list as unrestricted; depth 1 is
#     the operative brake until the model's blank-means-any semantics are
#     revisited — tracked with HIER-P0);
#   * Platform Architect: `moderate`, max_depth 3, may delegate to every
#     Engineering agent — written in the CONSUMER's vocabulary, the agent
#     TYPES its children carry (the column is compared against
#     Ai::Agent#agent_type by every reader), derived from the children so a
#     new Engineering agent of a new type widens it without a second edit;
#   * Platform Developer: `conservative`, max_depth 1, may delegate review to
#     the LLM Judge's type only;
#   * Release Manager: delegates to NOBODY. Ai::DelegationPolicy validates
#     max_depth > 0 and reads an empty type list as "any", so "nobody" is
#     spelled as a delegate-type list no agent can carry (RELEASE_MANAGER_NO_DELEGATES);
#   * every other Engineering child: the core-forest leaf policy.
#
# The lineage table needs an owning account (a global agent has none): the
# platform admin account, the same one the extension agent seeds key their
# per-account policy rows on. The delegation rows are keyed on that SAME
# account rather than as canonical account_id-NULL rows, so the seed is correct
# under both the pre- and post-HIER-P0 delegation-policy schema (the older one
# has account_id NOT NULL); another account may still hold its own row, which
# Ai::DelegationPolicy.resolve_for prefers.

CORE_HIERARCHY_ROOT_SLUG = "powernode-assistant"

CORE_HIERARCHY_CHILD_SLUGS = %w[
  system-performance-monitor
  system-analytics-intelligence
  system-health-monitor
  infrastructure-health-monitor
  process-automation-optimizer
  visual-design-assistant
  rag-reranker
  rag-query-engine
  intent-classifier
].freeze

ENGINEERING_HIERARCHY_ROOT_SLUG = "platform-architect"

ENGINEERING_HIERARCHY_CHILD_SLUGS = %w[
  platform-developer
  release-manager
  documentation-specialist
  research-analyst
  strategic-planner
  prd-generator
  llm-judge
  system-quality-assurance
  knowledge-graph-curator
].freeze

CORE_HIERARCHY_CHILD_DELEGATION = {
  inheritance_policy: "conservative",
  max_depth: 1,
  allowed_delegate_types: [],
  allowed_actions: []
}.freeze

ENGINEERING_ROOT_DELEGATION = {
  inheritance_policy: "moderate",
  max_depth: 3,
  allowed_actions: []
}.freeze

PLATFORM_DEVELOPER_REVIEWER_SLUG = "llm-judge"
RELEASE_MANAGER_NO_DELEGATES = %w[none].freeze

puts "\n🌳 Seeding core agent hierarchy (canonicals under Powernode Assistant, Engineering under Platform Architect)..."

hierarchy_account = Account.find_by(name: "Powernode Admin") || Account.first

# Attach `child_slugs` under the global agent `root_slug`, writing each
# child's delegation policy from `delegation_for.call(child)`. Reports the
# root as absent (skipped) rather than raising, like the P1 seed did.
attach_forest = lambda do |writer, root_slug:, child_slugs:, delegation_for:|
  root = Ai::Agent.global.find_by(slug: root_slug)
  if root.nil?
    puts "  ⚠️  Global #{root_slug} not seeded yet — skipping its forest (re-run after its agent seed)"
    next
  end

  attached = 0
  missing = []
  child_slugs.each do |slug|
    child = Ai::Agent.global.find_by(slug: slug)
    if child.nil?
      missing << slug
      next
    end

    writer.attach!(child: child, parent: root, spawn_reason: "seed")
    writer.ensure_delegation_policy!(agent: child, **delegation_for.call(child))
    attached += 1
  end

  puts "  ✅ #{attached} canonical agents attached under #{root.name}"
  puts "  ⚠️  Not yet seeded (skipped): #{missing.join(', ')}" if missing.any?
  root
end

if hierarchy_account.nil?
  puts "  ⚠️  No account exists to own the lineage rows — skipping hierarchy (re-run after setup)"
else
  writer = Ai::Agents::HierarchyWriter.new(account: hierarchy_account)

  attach_forest.call(
    writer,
    root_slug: CORE_HIERARCHY_ROOT_SLUG,
    child_slugs: CORE_HIERARCHY_CHILD_SLUGS,
    delegation_for: ->(_child) { CORE_HIERARCHY_CHILD_DELEGATION }
  )

  reviewer_type = Ai::Agent.global.find_by(slug: PLATFORM_DEVELOPER_REVIEWER_SLUG)&.agent_type
  if reviewer_type.blank?
    puts "  ⚠️  #{PLATFORM_DEVELOPER_REVIEWER_SLUG} not seeded — Platform Developer delegates to " \
         "NOBODY until it is (an empty type list would mean UNRESTRICTED)"
  end
  engineering_delegation = lambda do |child|
    case child.slug
    when "platform-developer"
      # NARROW when the reviewer is missing, never widen. Ai::DelegationPolicy
      # reads an EMPTY allowed_delegate_types as "any type" (#allows_delegate_type?
      # is `blank? || include?`), so `[reviewer_type].compact` on an install
      # where llm-judge has not been seeded — a state the graceful-skip contract
      # makes expected — would hand the Platform Developer unrestricted
      # delegation. Fall back to the same no-such-type sentinel the Release
      # Manager carries.
      types = reviewer_type.present? ? [ reviewer_type ] : RELEASE_MANAGER_NO_DELEGATES
      CORE_HIERARCHY_CHILD_DELEGATION.merge(allowed_delegate_types: types)
    when "release-manager"
      CORE_HIERARCHY_CHILD_DELEGATION.merge(allowed_delegate_types: RELEASE_MANAGER_NO_DELEGATES)
    else
      CORE_HIERARCHY_CHILD_DELEGATION
    end
  end

  engineering_root = attach_forest.call(
    writer,
    root_slug: ENGINEERING_HIERARCHY_ROOT_SLUG,
    child_slugs: ENGINEERING_HIERARCHY_CHILD_SLUGS,
    delegation_for: engineering_delegation
  )

  if engineering_root
    # Same fail-open hazard as the Platform Developer's list above: with none of
    # the children seeded this pluck is empty, which the model reads as
    # unrestricted. Fall back to the sentinel.
    child_types = Ai::Agent.global.where(slug: ENGINEERING_HIERARCHY_CHILD_SLUGS).distinct.pluck(:agent_type).sort
    child_types = RELEASE_MANAGER_NO_DELEGATES if child_types.empty?
    writer.ensure_delegation_policy!(
      agent: engineering_root,
      **ENGINEERING_ROOT_DELEGATION.merge(allowed_delegate_types: child_types)
    )
    puts "  ✅ Platform Architect delegation: moderate, depth 3, may delegate to #{child_types.join(', ')}"
  end
end
