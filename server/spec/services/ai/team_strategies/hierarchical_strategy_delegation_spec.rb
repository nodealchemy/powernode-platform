# frozen_string_literal: true

require "rails_helper"

# HIER-P4 team execution smoke: `execute_team` on the seeded Platform
# Engineering team dispatches to the worker, and the manager_led strategy the
# worker calls back into runs under the DELEGATION POLICIES — the manager
# delegates a subtask only to a member whose agent_type its Ai::DelegationPolicy
# admits (Ai::Autonomy::DelegationAuthorityService); a member outside
# allowed_delegate_types is refused, recorded, and never executed.
module PlatformEngineeringSmokeSeeds
  SEED_FILES = %w[
    claude_agents_seed.rb
    monitoring_analytics_agents_seed.rb
    ai_utility_agents_seed.rb
    ai_concierge_seed.rb
    autonomy_data_seed.rb
    ai_engineering_agents_seed.rb
    ai_agent_hierarchy_seed.rb
    ai_canonical_teams_seed.rb
  ].freeze
end

RSpec.describe Ai::TeamStrategies::HierarchicalStrategy, "under the delegation policies" do
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

  before { PlatformEngineeringSmokeSeeds::SEED_FILES.each { |f| load_seed!(f) } }

  let(:template) { Ai::TeamTemplate.global.find_by!(slug: "platform-engineering") }
  let(:team)     { account.ai_agent_teams.find_by!(template_id: template.id) }
  let(:task)     { "Research: summarise the current state of the module build pipeline in three bullets." }

  describe "execute_team (MCP verb)" do
    it "dispatches the canonical team to the worker" do
      expect(WorkerJobService).to receive(:enqueue_ai_team_execution)
        .with(hash_including(team_id: team.id, input: { "task" => task }))
        .and_return({ "success" => true })

      result = Ai::Tools::TeamManagementTool.new(account: account, user: user)
                                            .execute(params: { action: "execute_team", team_id: "Platform Engineering",
                                                               input: { task: task } })

      expect(result[:success]).to be true
      expect(result[:team_id]).to eq(team.id)
      expect(result[:status]).to eq("execution_dispatched")
    end
  end

  describe "the manager_led strategy" do
    let!(:outsider) do
      create(:ai_agent, account: account, provider: anthropic, name: "Poster Painter", agent_type: "image_generator")
    end
    let!(:outsider_member) { team.members.create!(agent: outsider, role: "executor") }
    let(:execution) { create(:ai_team_execution, account: account, agent_team: team, triggered_by: user) }
    let(:strategy)  { described_class.new(team: team, execution: execution, account: account) }
    let(:executed)  { [] }

    before do
      llm = instance_double(WorkerLlmClient)
      allow(llm).to receive(:complete).and_return(double(content: "Final synthesis"))
      allow_any_instance_of(described_class).to receive(:build_llm_client).and_return(llm)

      # One subtask per ADMITTED worker (the outsider is refused before the
      # decomposition sees the pool), so every admitted member runs exactly once.
      admitted_workers = team.members.non_leads.count - 1
      subtasks = Array.new(admitted_workers) { |i| { description: "subtask #{i + 1} of #{task}" } }
      allow_any_instance_of(Ai::Planning::TaskDecompositionService).to receive(:decompose)
        .and_return({ subtasks: subtasks })

      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute) do |executor, params|
        executed << executor.instance_variable_get(:@agent)
        { output: "done: #{params['input']}", cost: 0.0, tokens_used: 1 }
      end
    end

    it "runs every admitted member on the account's principals and refuses the member outside the manager's delegate types" do
      results = strategy.execute(input: task)

      lead = team.lead_agent
      expect(lead.cloned_from.slug).to eq("platform-architect")
      policy = Ai::DelegationPolicy.resolve_for(agent_id: lead.id, account_id: account.id)
      expect(policy.allows_delegate_type?("image_generator")).to be false

      expect(executed).not_to include(outsider)
      expect(executed.map(&:account_id).uniq).to eq([ account.id ])
      expect(executed.map(&:global?).uniq).to eq([ false ])
      admitted = team.members.non_leads.includes(:agent).map(&:agent) - [ outsider ]
      expect(executed).to match_array(admitted)

      refusal = results[:outputs].find { |o| o[:agent_id] == outsider.id }
      expect(refusal).to be_present
      expect(refusal[:output]).to be_nil
      expect(refusal[:refused]).to match(/image_generator/)
      expect(results[:tasks_failed]).to eq(1)
      expect(results[:tasks_completed]).to eq(admitted.size + 1)
      expect(results[:outputs].last[:output]).to eq("Final synthesis")
    end

    it "falls back to the manager alone when no member may be delegated to" do
      lead = team.lead_agent
      Ai::Agents::HierarchyWriter.new(account: account)
                                 .ensure_delegation_policy!(agent: lead, allowed_delegate_types: %w[none])

      results = strategy.execute(input: task)

      expect(executed).to eq([ lead ])
      expect(results[:outputs].count { |o| o[:refused].present? }).to eq(team.members.non_leads.count)
    end
  end
end
