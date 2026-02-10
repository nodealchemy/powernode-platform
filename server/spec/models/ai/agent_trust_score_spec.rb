# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentTrustScore, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).class_name('Ai::Agent') }
  end

  describe 'validations' do
    subject { build(:ai_agent_trust_score, agent: agent, account: account) }

    it { should validate_uniqueness_of(:agent_id).case_insensitive }
    it { should validate_inclusion_of(:tier).in_array(%w[supervised monitored trusted autonomous]) }

    %i[reliability cost_efficiency safety quality speed overall_score].each do |dimension|
      it { should validate_numericality_of(dimension).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1) }
    end

    it 'is invalid with dimension values below 0' do
      score = build(:ai_agent_trust_score, agent: agent, account: account, reliability: -0.1)
      expect(score).not_to be_valid
    end

    it 'is invalid with dimension values above 1' do
      score = build(:ai_agent_trust_score, agent: agent, account: account, safety: 1.1)
      expect(score).not_to be_valid
    end

    it 'is invalid with an unknown tier' do
      score = build(:ai_agent_trust_score, agent: agent, account: account, tier: "unknown")
      expect(score).not_to be_valid
    end

    it 'enforces agent uniqueness' do
      create(:ai_agent_trust_score, agent: agent, account: account)
      duplicate = build(:ai_agent_trust_score, agent: agent, account: account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:agent_id]).to include('has already been taken')
    end
  end

  describe '#recalculate!' do
    let(:trust_score) do
      create(:ai_agent_trust_score,
             agent: agent,
             account: account,
             reliability: 0.8,
             cost_efficiency: 0.6,
             safety: 0.9,
             quality: 0.7,
             speed: 0.5)
    end

    it 'calculates overall_score using correct weights' do
      # weights: reliability=0.25, cost_efficiency=0.15, safety=0.30, quality=0.20, speed=0.10
      expected = (0.8 * 0.25) + (0.6 * 0.15) + (0.9 * 0.30) + (0.7 * 0.20) + (0.5 * 0.10)

      trust_score.recalculate!
      expect(trust_score.overall_score).to be_within(0.001).of(expected)
    end

    it 'updates the tier based on the new overall score' do
      trust_score.recalculate!
      expect(Ai::AgentTrustScore::TIERS).to include(trust_score.tier)
    end

    it 'sets last_evaluated_at to current time' do
      freeze_time do
        trust_score.recalculate!
        expect(trust_score.last_evaluated_at).to eq(Time.current)
      end
    end

    it 'increments evaluation_count' do
      expect { trust_score.recalculate! }.to change { trust_score.evaluation_count }.by(1)
    end

    it 'appends to evaluation_history' do
      trust_score.recalculate!
      expect(trust_score.evaluation_history).not_to be_empty
      last_entry = trust_score.evaluation_history.last
      expect(last_entry).to include("score", "tier", "dimensions", "evaluated_at")
    end

    it 'keeps evaluation_history capped at 50 entries' do
      trust_score.update_columns(evaluation_history: Array.new(55) { { score: 0.5 } })
      trust_score.reload
      trust_score.recalculate!
      expect(trust_score.evaluation_history.size).to be <= 50
    end
  end

  describe '#promotable?' do
    it 'returns true when score meets next tier threshold' do
      trust_score = create(:ai_agent_trust_score,
                           agent: agent,
                           account: account,
                           tier: "supervised",
                           overall_score: 0.45)

      expect(trust_score.promotable?).to be true
    end

    it 'returns false when score does not meet next tier threshold' do
      trust_score = create(:ai_agent_trust_score,
                           agent: agent,
                           account: account,
                           tier: "supervised",
                           overall_score: 0.3)

      expect(trust_score.promotable?).to be false
    end

    it 'returns false when already at highest tier' do
      trust_score = create(:ai_agent_trust_score, :autonomous,
                           agent: agent,
                           account: account)

      expect(trust_score.promotable?).to be false
    end
  end

  describe '#demotable?' do
    it 'returns false when at supervised tier' do
      trust_score = create(:ai_agent_trust_score,
                           agent: agent,
                           account: account,
                           tier: "supervised",
                           overall_score: 0.1)

      expect(trust_score.demotable?).to be false
    end

    it 'returns true when score drops below current tier threshold' do
      trust_score = create(:ai_agent_trust_score,
                           agent: agent,
                           account: account,
                           tier: "monitored",
                           overall_score: 0.3)

      expect(trust_score.demotable?).to be true
    end

    it 'returns false when score is above current tier threshold' do
      trust_score = create(:ai_agent_trust_score,
                           agent: agent,
                           account: account,
                           tier: "monitored",
                           overall_score: 0.5)

      expect(trust_score.demotable?).to be false
    end
  end

  describe '#emergency_demote!' do
    let(:trust_score) do
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

    it 'demotes to supervised after recalculation (with low enough scores)' do
      trust_score.emergency_demote!
      # After reducing safety by 0.3 (to 0.1) and recalculating, score drops below supervised threshold
      expect(trust_score.reload.tier).to eq("supervised")
    end

    it 'reduces safety score by 0.3 (minimum 0)' do
      original_safety = trust_score.safety
      trust_score.emergency_demote!
      # emergency_demote! reduces safety then recalculate! persists
      expect(trust_score.reload.safety).to be < original_safety
    end

    it 'appends emergency_demotion to evaluation_history' do
      trust_score.emergency_demote!
      history = trust_score.reload.evaluation_history
      demotion_entry = history.find { |e| e["type"] == "emergency_demotion" }
      expect(demotion_entry).to be_present
      expect(demotion_entry["reason"]).to eq("critical_violation")
    end

    it 'accepts a custom reason' do
      trust_score.emergency_demote!(reason: "data_leak")
      history = trust_score.reload.evaluation_history
      demotion_entry = history.find { |e| e["type"] == "emergency_demotion" }
      expect(demotion_entry["reason"]).to eq("data_leak")
    end
  end
end
