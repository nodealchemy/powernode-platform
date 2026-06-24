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
end
