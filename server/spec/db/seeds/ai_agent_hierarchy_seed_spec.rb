# frozen_string_literal: true

require "rails_helper"

# HIER-P1 (extended by HIER-P2B-ENG) — the core canonical agents hang under
# TWO core roots as seeded data: the fundamental core forest under the core
# concierge (Powernode Assistant) and the Engineering hierarchy under the
# Platform Architect. One active Ai::AgentLineage edge and one
# Ai::DelegationPolicy row each, written through Ai::Agents::HierarchyWriter.
# Both roots are parentless in CORE — the system extension's hierarchy seed
# attaches them under System Concierge (core never reaches for an extension
# agent). The Engineering forest's own shape (which child hangs where, the
# per-agent delegation) is pinned in ai_engineering_agents_seed_spec.rb; this
# file pins the INVARIANT — every global canonical the loaded seed files
# create is attached under exactly one of the two roots.
#
# The child lists are pinned against the seed FILES this spec loads: every
# GLOBAL agent those files create (other than the roots) must be attached, so
# a new core canonical added to one of them fails here rather than shipping as
# a "standalone" node on the Autonomy page. A canonical introduced by a NEW
# seed file is covered only once that file joins the list below — keep the two
# in step with db/seeds.rb's baseline agent block.
module CoreAgentHierarchySeeds
  SEED_FILES = %w[
    claude_agents_seed.rb
    monitoring_analytics_agents_seed.rb
    ai_utility_agents_seed.rb
    ai_concierge_seed.rb
    autonomy_data_seed.rb
    ai_engineering_agents_seed.rb
  ].freeze

  ROOT_SLUGS = %w[powernode-assistant platform-architect].freeze
end

RSpec.describe "ai_agent_hierarchy_seed" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account)   { create(:account, name: "Powernode Admin") }
  let!(:user)      { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }
  let!(:openai)    { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let!(:ollama)    { create(:ai_provider, account: account, provider_type: "ollama", is_active: true) }
  let!(:grok)      { create(:ai_provider, account: account, provider_type: "custom", is_active: true) }
  # ai_concierge_seed binds the concierge skill and raises without it (it runs
  # after ai_skills_seed in db/seeds.rb); the row is all the seed needs here.
  let!(:concierge_skill) { create(:ai_skill, account: account, slug: "powernode-concierge", name: "Powernode Concierge") }

  let(:root) { Ai::Agent.global.find_by(slug: "powernode-assistant") }
  let(:engineering_root) { Ai::Agent.global.find_by(slug: "platform-architect") }
  let(:roots) { [ root, engineering_root ] }

  def seed_all!
    CoreAgentHierarchySeeds::SEED_FILES.each { |f| load_seed!(f) }
    load_seed!("ai_agent_hierarchy_seed.rb")
  end

  def canonical_children
    Ai::Agent.global.where.not(slug: CoreAgentHierarchySeeds::ROOT_SLUGS)
  end

  it "attaches every core canonical agent under exactly ONE of the two core roots with exactly one active edge" do
    seed_all!

    expect(root).to be_present
    expect(root.is_concierge).to be true
    expect(engineering_root).to be_present
    expect(engineering_root.is_governance).to be true
    expect(canonical_children.count).to be > 0

    root_ids = roots.map(&:id)
    unattached = canonical_children.reject do |agent|
      edges = Ai::AgentLineage.for_child(agent.id).active
      edges.count == 1 && root_ids.include?(edges.first.parent_agent_id) &&
        agent.parent_agent_id == edges.first.parent_agent_id
    end
    expect(unattached.map(&:slug)).to be_empty

    # Both roots are parentless in core: the extension attaches them.
    roots.each do |r|
      expect(Ai::AgentLineage.where(child_agent_id: r.id)).to be_empty
      expect(Ai::AgentLineage.for_parent(r.id).active.pluck(:spawn_reason).uniq).to eq([ "seed" ])
    end
  end

  it "hangs the Engineering agents under the Platform Architect and everything else under Powernode Assistant" do
    seed_all!

    # ENGINEERING_HIERARCHY_CHILD_SLUGS is the seed's own attach list (a
    # top-level constant the loaded seed file defines).
    engineering = Ai::AgentLineage.for_parent(engineering_root.id).active.map { |e| e.child_agent.slug }.sort
    expect(engineering).to eq(ENGINEERING_HIERARCHY_CHILD_SLUGS.sort)

    core_forest = Ai::AgentLineage.for_parent(root.id).active.map { |e| e.child_agent.slug }
    expect(core_forest & ENGINEERING_HIERARCHY_CHILD_SLUGS).to be_empty
    expect(core_forest).to include("system-performance-monitor", "intent-classifier")
  end

  # Keyed on the seeding account, not as an account_id-NULL canonical row, so
  # the seed is correct under both the pre- and post-HIER-P0 schema (the older
  # one has ai_delegation_policies.account_id NOT NULL). The two Engineering
  # exceptions (Platform Developer → the LLM Judge's type only, Release
  # Manager → nobody) are pinned in ai_engineering_agents_seed_spec.rb.
  it "writes one conservative, depth-1 policy per child, keyed on the seeding account, with no delegate types outside the Engineering exceptions" do
    seed_all!

    canonical_children.each do |agent|
      policies = Ai::DelegationPolicy.where(agent_id: agent.id)
      expect(policies.count).to eq(1), "#{agent.slug} should carry exactly one delegation policy"
      policy = policies.first
      expect(policy.account_id).to eq(account.id)
      expect(Ai::DelegationPolicy.resolve_for(agent_id: agent.id, account_id: account.id)).to eq(policy)
      expect(policy.inheritance_policy).to eq("conservative")
      expect(policy.max_depth).to eq(1)
      expect(policy.allowed_delegate_types).to eq([]) unless %w[platform-developer release-manager].include?(agent.slug)
      expect(policy.delegatable_actions).to eq([])
    end
  end

  it "gives the Engineering root its own moderate, depth-3 policy on the seeding account" do
    seed_all!

    policy = Ai::DelegationPolicy.resolve_for(agent_id: engineering_root.id, account_id: account.id)
    expect(policy.account_id).to eq(account.id)
    expect(policy.inheritance_policy).to eq("moderate")
    expect(policy.max_depth).to eq(3)
  end

  it "is idempotent: a re-run adds no edge and no policy" do
    seed_all!

    edges    = Ai::AgentLineage.count
    policies = Ai::DelegationPolicy.count

    load_seed!("ai_agent_hierarchy_seed.rb")

    expect(Ai::AgentLineage.count).to eq(edges)
    expect(Ai::DelegationPolicy.count).to eq(policies)
  end

  it "skips cleanly when neither root has been seeded yet" do
    expect { load_seed!("ai_agent_hierarchy_seed.rb") }.not_to raise_error
    expect(Ai::AgentLineage.count).to eq(0)
  end
end
