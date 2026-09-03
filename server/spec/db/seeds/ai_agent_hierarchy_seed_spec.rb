# frozen_string_literal: true

require "rails_helper"

# HIER-P1 — the core canonical agents hang under the core concierge (Powernode
# Assistant) as seeded data: one active Ai::AgentLineage edge and one
# Ai::DelegationPolicy row each, written through Ai::Agents::HierarchyWriter.
#
# The child list is pinned against the seed FILES this spec loads: every GLOBAL
# agent those files create (other than the root) must be attached, so a new core
# canonical added to one of them fails here rather than shipping as a
# "standalone" node on the Autonomy page. A canonical introduced by a NEW seed
# file is covered only once that file joins the list below — keep the two in
# step with db/seeds.rb's baseline agent block.
module CoreAgentHierarchySeeds
  SEED_FILES = %w[
    claude_agents_seed.rb
    monitoring_analytics_agents_seed.rb
    ai_utility_agents_seed.rb
    ai_concierge_seed.rb
    autonomy_data_seed.rb
  ].freeze
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

  def seed_all!
    CoreAgentHierarchySeeds::SEED_FILES.each { |f| load_seed!(f) }
    load_seed!("ai_agent_hierarchy_seed.rb")
  end

  def canonical_children
    Ai::Agent.global.where.not(id: root.id)
  end

  it "attaches every core canonical agent to Powernode Assistant with exactly one active edge" do
    seed_all!

    expect(root).to be_present
    expect(root.is_concierge).to be true
    expect(canonical_children.count).to be > 0

    unattached = canonical_children.reject do |agent|
      Ai::AgentLineage.for_child(agent.id).active.where(parent_agent_id: root.id).count == 1 &&
        Ai::AgentLineage.for_child(agent.id).active.count == 1 &&
        agent.parent_agent_id == root.id
    end
    expect(unattached.map(&:slug)).to be_empty
    expect(Ai::AgentLineage.where(child_agent_id: root.id)).to be_empty
    expect(Ai::AgentLineage.for_parent(root.id).active.pluck(:spawn_reason).uniq).to eq([ "seed" ])
  end

  # Keyed on the seeding account, not as an account_id-NULL canonical row, so
  # the seed is correct under both the pre- and post-HIER-P0 schema (the older
  # one has ai_delegation_policies.account_id NOT NULL).
  it "writes one conservative, depth-1, no-delegate-type policy per child, keyed on the seeding account" do
    seed_all!

    canonical_children.each do |agent|
      policies = Ai::DelegationPolicy.where(agent_id: agent.id)
      expect(policies.count).to eq(1), "#{agent.slug} should carry exactly one delegation policy"
      policy = policies.first
      expect(policy.account_id).to eq(account.id)
      expect(Ai::DelegationPolicy.resolve_for(agent_id: agent.id, account_id: account.id)).to eq(policy)
      expect(policy.inheritance_policy).to eq("conservative")
      expect(policy.max_depth).to eq(1)
      expect(policy.allowed_delegate_types).to eq([])
      expect(policy.delegatable_actions).to eq([])
    end
  end

  it "is idempotent: a re-run adds no edge and no policy" do
    seed_all!

    edges    = Ai::AgentLineage.count
    policies = Ai::DelegationPolicy.count

    load_seed!("ai_agent_hierarchy_seed.rb")

    expect(Ai::AgentLineage.count).to eq(edges)
    expect(Ai::DelegationPolicy.count).to eq(policies)
  end

  it "skips cleanly when the root concierge has not been seeded yet" do
    expect { load_seed!("ai_agent_hierarchy_seed.rb") }.not_to raise_error
    expect(Ai::AgentLineage.count).to eq(0)
  end
end
