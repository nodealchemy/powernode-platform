# frozen_string_literal: true

require "rails_helper"

# HIER-P4 — the "Platform Engineering" team as seeded data: a global canonical
# Ai::TeamTemplate (source_key-managed, idempotent) materialised for the admin
# account as a hierarchical / manager_led / hub_spoke Ai::AgentTeam whose
# manager is the Platform Architect and whose members are the Engineering
# agents the HIER-P2B-ENG lineage hangs under it — on the account's executing
# principals (ruling 8), never on the canonicals themselves. Team, lineage and
# delegation are three views of one structure, so a freshly seeded install
# reports NO team drift.
module CanonicalTeamsSeeds
  AGENT_SEED_FILES = %w[
    claude_agents_seed.rb
    monitoring_analytics_agents_seed.rb
    ai_utility_agents_seed.rb
    ai_concierge_seed.rb
    autonomy_data_seed.rb
    ai_engineering_agents_seed.rb
    ai_agent_hierarchy_seed.rb
  ].freeze

  TEMPLATE_SLUG = "platform-engineering"

  # slug => [member role, lead?]
  ROSTER = {
    "platform-architect"       => [ "manager",    true ],
    "platform-developer"       => [ "executor",   false ],
    "release-manager"          => [ "executor",   false ],
    "research-analyst"         => [ "researcher", false ],
    "strategic-planner"        => [ "researcher", false ],
    "prd-generator"            => [ "writer",     false ],
    "llm-judge"                => [ "reviewer",   false ],
    "system-quality-assurance" => [ "reviewer",   false ],
    "documentation-specialist" => [ "writer",     false ],
    "knowledge-graph-curator"  => [ "analyst",    false ]
  }.freeze
end

RSpec.describe "ai_canonical_teams_seed" do
  RSpec::Matchers.define_negated_matcher :not_change, :change

  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account)   { create(:account, name: "Powernode Admin") }
  let!(:user)      { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }
  let!(:openai)    { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let!(:ollama)    { create(:ai_provider, account: account, provider_type: "ollama", is_active: true) }
  let!(:grok)      { create(:ai_provider, account: account, provider_type: "custom", is_active: true) }
  let!(:concierge_skill) { create(:ai_skill, account: account, slug: "powernode-concierge", name: "Powernode Concierge") }

  def seed_all!
    CanonicalTeamsSeeds::AGENT_SEED_FILES.each { |f| load_seed!(f) }
    load_seed!("ai_canonical_teams_seed.rb")
  end

  let(:template) { Ai::TeamTemplate.global.find_by(slug: CanonicalTeamsSeeds::TEMPLATE_SLUG) }
  let(:team)     { account.ai_agent_teams.find_by(template_id: template.id) }
  let(:architect) { Ai::Agent.global.find_by!(slug: "platform-architect") }

  def canonical_of(member) = member.agent.cloned_from

  it "seeds the Platform Engineering template as a global, is_system, source_key-managed canonical" do
    seed_all!

    expect(template).to be_present
    expect(template).to be_global
    expect(template.is_system).to be true
    expect(template.source_key).to eq(CanonicalTeamsSeeds::TEMPLATE_SLUG)
    expect(template.name).to eq("Platform Engineering")
    expect(template.team_topology).to eq("hierarchical")
    expect(template.default_config).to include("coordination_strategy" => "manager_led",
                                               "communication_pattern" => "hub_spoke")
    expect(template.member_definitions.map { |d| d["agent_slug"] }).to eq(CanonicalTeamsSeeds::ROSTER.keys)
    expect(template.manager_definition["agent_slug"]).to eq("platform-architect")
  end

  it "materialises the team on the admin account with the Platform Architect's principal as manager" do
    seed_all!

    expect(team).to be_present
    expect(team).to be_canonical
    expect(team.team_type).to eq("hierarchical")
    expect(team.team_topology).to eq("hierarchical")
    expect(team.coordination_strategy).to eq("manager_led")
    expect(team.communication_pattern).to eq("hub_spoke")
    expect(team.status).to eq("active")

    members = team.members.includes(:agent).by_priority.to_a
    expect(members.size).to eq(CanonicalTeamsSeeds::ROSTER.size)
    expect(members.map { |m| canonical_of(m).slug }).to eq(CanonicalTeamsSeeds::ROSTER.keys)
    expect(members.map(&:role)).to eq(CanonicalTeamsSeeds::ROSTER.values.map(&:first))
    expect(members.map(&:is_lead)).to eq(CanonicalTeamsSeeds::ROSTER.values.map(&:last))

    # Ruling 8: every member is the account's executing principal, never a canonical.
    expect(members.map { |m| m.agent.account_id }.uniq).to eq([ account.id ])
    expect(members.map { |m| m.agent.global? }.uniq).to eq([ false ])
    expect(team.lead_agent.cloned_from_id).to eq(architect.id)

    expect(team.ai_team_roles.count).to eq(CanonicalTeamsSeeds::ROSTER.size)
    expect(team.ai_team_roles.find_by(ai_agent_id: team.lead_agent.id).role_type).to eq("manager")
  end

  it "agrees with the lineage forest and the delegation graph — no drift on a fresh seed" do
    seed_all!

    report = Ai::Teams::CanonicalTeamReconciler.new(account: account, template: template).drift
    expect(report.missing_edges).to be_empty
    expect(report.undelegatable_members).to be_empty
    expect(report.unrepresented_delegate_types).to be_empty
    expect(report.missing_members).to be_empty
    expect(report).not_to be_drifted
  end

  it "is idempotent: a re-run creates no template, team, member or agent" do
    seed_all!

    expect { load_seed!("ai_canonical_teams_seed.rb") }
      .to not_change(Ai::TeamTemplate, :count)
      .and not_change(Ai::AgentTeam, :count)
      .and not_change(Ai::AgentTeamMember, :count)
      .and not_change(Ai::Agent, :count)
  end

  it "reports a removed lineage edge as team drift" do
    seed_all!
    judge = Ai::Agent.global.find_by!(slug: "llm-judge")
    Ai::AgentLineage.find_by!(parent_agent_id: architect.id, child_agent_id: judge.id).terminate!(reason: "spec")

    report = Ai::Teams::CanonicalTeamReconciler.new(account: account, template: template).drift
    expect(report.missing_edges).to eq([ "platform-architect/llm-judge" ])
    expect(report).to be_drifted
  end

  it "skips gracefully when no account exists yet (canonical template only)" do
    # A fresh core/prod database before first-admin bootstrap: the seed's
    # account lookup finds nothing (the let! rows above cannot be destroyed
    # under the account's restrict-on-destroy dependents, so the lookup is
    # stubbed to the empty answer instead).
    allow(Account).to receive(:find_by).and_return(nil)
    allow(Account).to receive(:first).and_return(nil)

    expect { load_seed!("ai_canonical_teams_seed.rb") }.not_to raise_error
    expect(template).to be_present
    expect(Ai::AgentTeam.count).to eq(0)
  end
end
