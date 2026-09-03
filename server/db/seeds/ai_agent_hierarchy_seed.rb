# frozen_string_literal: true

# Core agent hierarchy (HIER-P1) — the fundamental GLOBAL platform agents hang
# under the core concierge (Powernode Assistant, `is_concierge`) as seeded
# data: one active Ai::AgentLineage edge each (spawn_reason "seed") and one
# Ai::DelegationPolicy row, written through Ai::Agents::HierarchyWriter — the
# same seam every runtime creation path uses, so the Autonomy page's lineage
# forest and the delegation checks describe one structure.
#
# Runs LAST in the baseline agent block (db/seeds.rb) so every canonical the
# agent seeds create already exists. Idempotent: a re-run changes nothing.
#
# The children are listed by slug, and spec/db/seeds/ai_agent_hierarchy_seed_spec.rb
# pins the list against the seed files it loads: every global agent those files
# create, other than the root, must carry exactly one edge, so a new canonical
# added to one of THOSE files fails the spec instead of shipping as a
# "standalone" node. A canonical introduced by a NEW seed file is only covered
# once that file is added to the spec's list too.
#
# Delegation for these agents (operator ruling 2026-09-03): they are
# single-purpose, so `conservative`, max_depth 1, no delegate types and no
# delegatable actions. (Ai::DelegationPolicy#allows_delegate_type? treats an
# EMPTY list as unrestricted; depth 1 is the operative brake until the model's
# blank-means-any semantics are revisited — tracked with HIER-P0.)
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
  strategic-planner
  research-analyst
  system-performance-monitor
  system-analytics-intelligence
  system-health-monitor
  system-quality-assurance
  infrastructure-health-monitor
  process-automation-optimizer
  visual-design-assistant
  prd-generator
  llm-judge
  knowledge-graph-curator
  rag-reranker
  rag-query-engine
  intent-classifier
].freeze

CORE_HIERARCHY_CHILD_DELEGATION = {
  inheritance_policy: "conservative",
  max_depth: 1,
  allowed_delegate_types: [],
  allowed_actions: []
}.freeze

puts "\n🌳 Seeding core agent hierarchy (canonicals under Powernode Assistant)..."

hierarchy_root = Ai::Agent.global.find_by(slug: CORE_HIERARCHY_ROOT_SLUG)
hierarchy_account = Account.find_by(name: "Powernode Admin") || Account.first

if hierarchy_root.nil?
  puts "  ⚠️  Global #{CORE_HIERARCHY_ROOT_SLUG} not seeded yet — skipping hierarchy (re-run after ai_concierge_seed)"
elsif hierarchy_account.nil?
  puts "  ⚠️  No account exists to own the lineage rows — skipping hierarchy (re-run after setup)"
else
  writer = Ai::Agents::HierarchyWriter.new(account: hierarchy_account)
  attached = 0
  missing = []

  CORE_HIERARCHY_CHILD_SLUGS.each do |slug|
    child = Ai::Agent.global.find_by(slug: slug)
    if child.nil?
      missing << slug
      next
    end

    writer.attach!(child: child, parent: hierarchy_root, spawn_reason: "seed")
    writer.ensure_delegation_policy!(agent: child, **CORE_HIERARCHY_CHILD_DELEGATION)
    attached += 1
  end

  puts "  ✅ #{attached} canonical agents attached under #{hierarchy_root.name} (delegation: conservative, depth 1)"
  puts "  ⚠️  Not yet seeded (skipped): #{missing.join(', ')}" if missing.any?
end
