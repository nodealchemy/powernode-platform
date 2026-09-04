# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TeamStrategies::MeshStrategy, type: :service do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, :mesh, account: account) }
  let(:execution) { create(:ai_team_execution, account: account, agent_team: team) }
  let(:strategy) { described_class.new(team: team, execution: execution, account: account) }

  let(:agent_a) { create(:ai_agent, account: account) }
  let(:agent_b) { create(:ai_agent, account: account) }

  before do
    allow(Rails.logger).to receive(:info)
  end

  describe '#check_consensus (all-failed round)' do
    # When every agent in a round fails, the round outputs all have output: nil,
    # so `completed` is empty. Dereferencing completed.first[:output] raised a
    # NoMethodError that was silently swallowed by the broad rescue. An all-failed
    # round is an expected (not exceptional) condition, so it must be handled
    # cleanly without triggering the consensus-check error path.
    let(:all_failed_round) do
      [
        { agent_id: agent_a.id, agent_name: agent_a.name, role: 'collaborator', output: nil },
        { agent_id: agent_b.id, agent_name: agent_b.name, role: 'collaborator', output: nil }
      ]
    end

    it 'handles the empty case without logging an internal consensus-check error' do
      expect(Rails.logger).not_to receive(:error).with(/Consensus check failed/)

      strategy.send(:check_consensus, agent_a, 'do the task', all_failed_round)
    end

    it 'reports no consensus and nil synthesis for an all-failed round' do
      result = strategy.send(:check_consensus, agent_a, 'do the task', all_failed_round)

      expect(result[:consensus_reached]).to be(false)
      expect(result[:synthesis]).to be_nil
    end
  end

  # A round with two real outputs is the only path that reaches the LLM. It
  # asked the evaluator for `model_id`, which Ai::Agent does not define — and
  # the broad rescue turned that NoMethodError into a silent
  # `consensus_reached: false`, so mesh teams never reached consensus and
  # nothing surfaced. HierarchicalStrategy had the same bug until HIER-P4;
  # `resolved_model` is the accessor both must use.
  describe '#check_consensus (multi-output round reaches the LLM)' do
    let(:llm_client) { instance_double(WorkerLlmClient) }
    let(:completed_round) do
      [
        { agent_id: agent_a.id, agent_name: agent_a.name, role: 'collaborator', output: 'A says yes' },
        { agent_id: agent_b.id, agent_name: agent_b.name, role: 'collaborator', output: 'B says yes' }
      ]
    end

    before do
      allow(strategy).to receive(:build_llm_client).with(agent_a).and_return(llm_client)
    end

    it 'passes the evaluator resolved model, not a nonexistent model_id' do
      expect(llm_client).to receive(:complete_structured)
        .with(hash_including(model: agent_a.resolved_model))
        .and_return({ 'consensus_reached' => true, 'synthesis' => 'agreed' })

      strategy.send(:check_consensus, agent_a, 'do the task', completed_round)
    end

    it 'returns the synthesis instead of swallowing an internal error' do
      allow(llm_client).to receive(:complete_structured)
        .and_return({ 'consensus_reached' => true, 'synthesis' => 'agreed' })
      expect(Rails.logger).not_to receive(:error).with(/Consensus check failed/)

      result = strategy.send(:check_consensus, agent_a, 'do the task', completed_round)

      expect(result[:consensus_reached]).to be(true)
      expect(result[:synthesis]).to eq('agreed')
    end
  end
end
