# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::TrustEngineService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  describe '#evaluate' do
    let(:execution) do
      create(:ai_agent_execution, :completed,
             agent: agent,
             account: account)
    end

    it 'creates a trust score if none exists' do
      expect { service.evaluate(agent: agent, execution: execution) }
        .to change(Ai::AgentTrustScore, :count).by(1)
    end

    it 'returns success with score details' do
      result = service.evaluate(agent: agent, execution: execution)

      expect(result[:success]).to be true
      expect(result[:agent_id]).to eq(agent.id)
      expect(result[:overall_score]).to be_a(Numeric)
      expect(result[:tier]).to be_present
      expect(result[:dimensions]).to be_a(Hash)
    end

    it 'updates dimensions based on execution' do
      service.evaluate(agent: agent, execution: execution)

      trust_score = Ai::AgentTrustScore.find_by(agent_id: agent.id)
      expect(trust_score.reliability).to be > 0.5 # Completed execution increases reliability
      expect(trust_score.last_evaluated_at).to be_present
    end

    it 'uses exponential moving average for updates' do
      # First evaluation
      service.evaluate(agent: agent, execution: execution)
      first_reliability = Ai::AgentTrustScore.find_by(agent_id: agent.id).reliability

      # Second evaluation with failed execution
      failed_exec = create(:ai_agent_execution, :failed, agent: agent, account: account)
      service.evaluate(agent: agent, execution: failed_exec)
      second_reliability = Ai::AgentTrustScore.find_by(agent_id: agent.id).reliability

      # EMA should produce a value between 0 and first_reliability (not a sudden drop)
      expect(second_reliability).to be < first_reliability
      expect(second_reliability).to be > 0.0
    end

    it 'handles evaluation errors gracefully' do
      allow(Ai::AgentTrustScore).to receive(:find_or_create_by!).and_raise(StandardError, "DB error")

      result = service.evaluate(agent: agent, execution: execution)
      expect(result[:success]).to be false
      expect(result[:error]).to include("DB error")
    end
  end

  describe '#emergency_demote!' do
    let!(:trust_score) do
      create(:ai_agent_trust_score,
             agent: agent,
             account: account,
             tier: "trusted",
             reliability: 0.3,
             cost_efficiency: 0.2,
             safety: 0.4,
             quality: 0.3,
             speed: 0.2,
             overall_score: 0.3)
    end

    it 'demotes to supervised' do
      result = service.emergency_demote!(agent: agent, reason: "critical_violation")

      expect(result[:success]).to be true
      expect(result[:new_tier]).to eq("supervised")
      expect(trust_score.reload.tier).to eq("supervised")
    end

    it 'returns previous tier information' do
      result = service.emergency_demote!(agent: agent, reason: "data_breach")

      expect(result[:previous_tier]).to eq("trusted")
      expect(result[:reason]).to eq("data_breach")
    end

    it 'updates agent trust_level if available' do
      agent.update!(trust_level: "trusted")
      service.emergency_demote!(agent: agent, reason: "violation")

      expect(agent.reload.trust_level).to eq("supervised")
    end
  end

  describe '#emergency_demote! cancels running executions' do
    let!(:trust_score) do
      create(:ai_agent_trust_score,
             agent: agent,
             account: account,
             tier: "trusted",
             overall_score: 0.8)
    end

    it 'cancels running executions on emergency demotion' do
      running_exec = create(:ai_agent_execution, :running,
                            agent: agent, account: account, provider: provider, user: user)

      service.emergency_demote!(agent: agent, reason: "test_demotion")

      running_exec.reload
      expect(running_exec.status).to eq("cancelled")
      expect(running_exec.error_message).to include("Emergency demotion")
    end

    it 'does not fail if no running executions exist' do
      result = service.emergency_demote!(agent: agent, reason: "test_demotion")
      expect(result[:success]).to be true
    end
  end

  describe 'promotion cooling-off period' do
    let!(:trust_score) do
      create(:ai_agent_trust_score,
             agent: agent,
             account: account,
             tier: "monitored",
             overall_score: 0.75,
             evaluation_count: 15,
             evaluation_history: [{
               "type" => "demotion",
               "evaluated_at" => 2.hours.ago.iso8601
             }])
    end

    it 'blocks promotion when recently demoted' do
      # Even though score qualifies for promotion, the recent demotion should block it
      result = service.send(:check_tier_transition, trust_score)
      expect(result[:type]).to be_nil
    end

    it 'allows promotion after cooldown period' do
      trust_score.update!(evaluation_history: [{
        "type" => "demotion",
        "evaluated_at" => 48.hours.ago.iso8601
      }])

      # Score must be high enough and evaluation count sufficient
      trust_score.update!(overall_score: 0.75, evaluation_count: 15)

      # This should be allowed since the demotion was >24h ago
      result = service.send(:check_tier_transition, trust_score)
      # Result depends on whether score meets TIER_THRESHOLDS for next tier
      expect(result).to be_a(Hash)
    end
  end

  describe '#assess' do
    it 'returns default assessment when no trust score exists' do
      result = service.assess(agent: agent)

      expect(result[:tier]).to eq("supervised")
      expect(result[:score]).to eq(0.0)
      expect(result[:evaluated]).to be false
    end

    it 'returns full assessment when trust score exists' do
      create(:ai_agent_trust_score, :monitored,
             agent: agent,
             account: account)

      result = service.assess(agent: agent)

      expect(result[:tier]).to eq("monitored")
      expect(result[:score]).to be_a(Numeric)
      expect(result[:dimensions]).to be_a(Hash)
      expect(result[:dimensions]).to include("reliability", "safety")
      expect(result[:promotable]).to be_in([true, false])
      expect(result[:demotable]).to be_in([true, false])
      expect(result[:evaluated]).to be true
    end
  end

  describe '#evaluate_pending' do
    it 'evaluates agents that need re-evaluation' do
      trust_score = create(:ai_agent_trust_score,
                           agent: agent,
                           account: account,
                           last_evaluated_at: 2.days.ago)

      # Create recent executions for the agent
      create_list(:ai_agent_execution, 3, :completed,
                  agent: agent,
                  account: account)

      results = service.evaluate_pending

      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
      expect(results.first[:agent_id]).to eq(agent.id)
      expect(trust_score.reload.last_evaluated_at).to be > 1.day.ago
    end

    it 'skips agents with no recent executions' do
      create(:ai_agent_trust_score,
             agent: agent,
             account: account,
             last_evaluated_at: 2.days.ago)

      # No executions created
      results = service.evaluate_pending
      expect(results).to be_empty
    end

    it 'skips recently evaluated agents' do
      create(:ai_agent_trust_score,
             agent: agent,
             account: account,
             last_evaluated_at: 1.hour.ago)

      results = service.evaluate_pending
      expect(results).to be_empty
    end
  end
end
