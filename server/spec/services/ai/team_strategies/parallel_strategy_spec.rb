# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TeamStrategies::ParallelStrategy, type: :service do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, :parallel, account: account) }
  let(:execution) { create(:ai_team_execution, account: account, agent_team: team) }
  let(:strategy) { described_class.new(team: team, execution: execution, account: account) }

  let(:agent_a) { create(:ai_agent, account: account) }
  let(:agent_b) { create(:ai_agent, account: account) }

  let!(:member_a) { create(:ai_agent_team_member, team: team, agent: agent_a, role: 'worker', priority_order: 0) }
  let!(:member_b) { create(:ai_agent_team_member, team: team, agent: agent_b, role: 'worker', priority_order: 1) }

  before do
    allow(Rails.logger).to receive(:info)
  end

  describe '#build_results_from_dag' do
    # DagExecution exposes outputs via final_outputs (jsonb) and the
    # node_output accessor. There is NO node_results method/column, so the
    # previous implementation raised NoMethodError on every parallel run.
    # final_outputs is keyed by node id ("agent-<agent_id>") and each value
    # is the per-node result hash persisted by DagExecutor#execute_node.
    let(:dag_execution) do
      create(
        :ai_dag_execution,
        :completed,
        account: account,
        final_outputs: {
          "agent-#{agent_a.id}" => { "status" => "completed", "output" => "result A" },
          "agent-#{agent_b.id}" => { "status" => "completed", "output" => "result B" }
        }
      )
    end

    it 'returns each member output without raising' do
      members = [ member_a, member_b ]

      result = strategy.send(:build_results_from_dag, dag_execution, members)

      outputs = result[:outputs].map { |o| o[:output] }
      expect(outputs).to contain_exactly("result A", "result B")
      expect(result[:tasks_completed]).to eq(2)
      expect(result[:tasks_failed]).to eq(0)
    end
  end
end
