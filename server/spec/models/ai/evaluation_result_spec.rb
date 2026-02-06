# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::EvaluationResult, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).class_name('Ai::Agent') }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_evaluation_result) }

    it { should validate_presence_of(:execution_id) }
    it { should validate_presence_of(:evaluator_model) }
    it { should validate_presence_of(:scores) }
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let(:account) { create(:account) }
    let(:agent) { create(:ai_agent, account: account) }

    describe '.for_agent' do
      let(:other_agent) { create(:ai_agent, account: account) }
      let!(:result_a) { create(:ai_evaluation_result, account: account, agent: agent) }
      let!(:result_b) { create(:ai_evaluation_result, account: account, agent: other_agent) }

      it 'returns results for the specified agent' do
        expect(described_class.for_agent(agent.id)).to include(result_a)
        expect(described_class.for_agent(agent.id)).not_to include(result_b)
      end
    end

    describe '.recent' do
      let!(:old_result) { create(:ai_evaluation_result, account: account, agent: agent, created_at: 2.days.ago) }
      let!(:new_result) { create(:ai_evaluation_result, account: account, agent: agent, created_at: 1.minute.ago) }

      it 'returns results ordered by created_at desc' do
        results = described_class.recent
        expect(results.first).to eq(new_result)
      end

      it 'defaults to 50 records' do
        expect(described_class.recent.limit_value).to eq(50)
      end

      it 'accepts a custom limit' do
        expect(described_class.recent(5).limit_value).to eq(5)
      end
    end

    describe '.in_time_range' do
      let!(:old_result) { create(:ai_evaluation_result, account: account, agent: agent, created_at: 3.hours.ago) }
      let!(:recent_result) { create(:ai_evaluation_result, account: account, agent: agent, created_at: 30.minutes.ago) }

      it 'returns results within the specified time range' do
        results = described_class.in_time_range(1.hour.ago)
        expect(results).to include(recent_result)
        expect(results).not_to include(old_result)
      end

      it 'accepts a custom end time' do
        results = described_class.in_time_range(4.hours.ago, 2.hours.ago)
        expect(results).to include(old_result)
        expect(results).not_to include(recent_result)
      end
    end
  end

  # ==========================================
  # Instance Methods
  # ==========================================
  describe 'score accessors' do
    let(:account) { create(:account) }
    let(:agent) { create(:ai_agent, account: account) }

    let(:result_with_all_scores) do
      create(:ai_evaluation_result,
             account: account,
             agent: agent,
             scores: {
               'correctness' => 0.9,
               'completeness' => 0.8,
               'helpfulness' => 0.85,
               'safety' => 0.95
             })
    end

    let(:result_with_partial_scores) do
      create(:ai_evaluation_result,
             account: account,
             agent: agent,
             scores: {
               'correctness' => 0.7,
               'helpfulness' => 0.6
             })
    end

    let(:result_with_empty_scores) do
      build(:ai_evaluation_result,
            account: account,
            agent: agent,
            scores: { 'other_metric' => 0.5 })
    end

    describe '#correctness_score' do
      it 'returns the correctness score from scores hash' do
        expect(result_with_all_scores.correctness_score).to eq(0.9)
      end

      it 'returns nil when correctness score is not present' do
        expect(result_with_empty_scores.correctness_score).to be_nil
      end
    end

    describe '#completeness_score' do
      it 'returns the completeness score from scores hash' do
        expect(result_with_all_scores.completeness_score).to eq(0.8)
      end

      it 'returns nil when completeness score is not present' do
        expect(result_with_partial_scores.completeness_score).to be_nil
      end
    end

    describe '#helpfulness_score' do
      it 'returns the helpfulness score from scores hash' do
        expect(result_with_all_scores.helpfulness_score).to eq(0.85)
      end

      it 'returns nil when helpfulness score is not present' do
        expect(result_with_empty_scores.helpfulness_score).to be_nil
      end
    end

    describe '#safety_score' do
      it 'returns the safety score from scores hash' do
        expect(result_with_all_scores.safety_score).to eq(0.95)
      end

      it 'returns nil when safety score is not present' do
        expect(result_with_partial_scores.safety_score).to be_nil
      end
    end
  end

  describe '#average_score' do
    let(:account) { create(:account) }
    let(:agent) { create(:ai_agent, account: account) }

    it 'calculates the average of all present scores' do
      result = create(:ai_evaluation_result,
                      account: account,
                      agent: agent,
                      scores: {
                        'correctness' => 0.9,
                        'completeness' => 0.8,
                        'helpfulness' => 0.85,
                        'safety' => 0.95
                      })

      # (0.9 + 0.8 + 0.85 + 0.95) / 4 = 0.875
      expect(result.average_score).to eq(0.88)
    end

    it 'calculates the average with partial scores' do
      result = create(:ai_evaluation_result,
                      account: account,
                      agent: agent,
                      scores: {
                        'correctness' => 0.7,
                        'helpfulness' => 0.6
                      })

      # (0.7 + 0.6) / 2 = 0.65
      expect(result.average_score).to eq(0.65)
    end

    it 'returns nil when no standard scores are present' do
      result = build(:ai_evaluation_result,
                     account: account,
                     agent: agent,
                     scores: { 'custom_metric' => 0.5 })

      expect(result.average_score).to be_nil
    end

    it 'handles a single score' do
      result = create(:ai_evaluation_result,
                      account: account,
                      agent: agent,
                      scores: { 'safety' => 0.95 })

      expect(result.average_score).to eq(0.95)
    end

    it 'rounds to 2 decimal places' do
      result = create(:ai_evaluation_result,
                      account: account,
                      agent: agent,
                      scores: {
                        'correctness' => 0.33,
                        'completeness' => 0.33,
                        'helpfulness' => 0.34
                      })

      # (0.33 + 0.33 + 0.34) / 3 = 0.3333...
      expect(result.average_score).to eq(0.33)
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_evaluation_result)).to be_valid
    end
  end
end
