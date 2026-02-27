# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ImprovementRecommendation, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:approved_by).class_name('User').optional }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_improvement_recommendation) }

    it { should validate_presence_of(:recommendation_type) }
    it { should validate_presence_of(:target_type) }
    it { should validate_presence_of(:target_id) }
    it { should validate_presence_of(:confidence_score) }
    it { should validate_presence_of(:status) }

    it { should validate_inclusion_of(:recommendation_type).in_array(Ai::ImprovementRecommendation::RECOMMENDATION_TYPES) }
    it { should validate_inclusion_of(:status).in_array(Ai::ImprovementRecommendation::STATUSES) }

    describe 'confidence_score numericality' do
      it 'is valid with a score of 0' do
        rec = build(:ai_improvement_recommendation, confidence_score: 0)
        expect(rec).to be_valid
      end

      it 'is valid with a score of 1' do
        rec = build(:ai_improvement_recommendation, confidence_score: 1)
        expect(rec).to be_valid
      end

      it 'is valid with a score of 0.5' do
        rec = build(:ai_improvement_recommendation, confidence_score: 0.5)
        expect(rec).to be_valid
      end

      it 'is invalid with a score less than 0' do
        rec = build(:ai_improvement_recommendation, confidence_score: -0.1)
        expect(rec).not_to be_valid
        expect(rec.errors[:confidence_score]).to be_present
      end

      it 'is invalid with a score greater than 1' do
        rec = build(:ai_improvement_recommendation, confidence_score: 1.1)
        expect(rec).not_to be_valid
        expect(rec.errors[:confidence_score]).to be_present
      end
    end
  end

  # ==========================================
  # Constants
  # ==========================================
  describe 'constants' do
    it 'defines valid STATUSES' do
      expect(Ai::ImprovementRecommendation::STATUSES).to eq(%w[pending approved applied dismissed])
    end

    it 'defines valid RECOMMENDATION_TYPES' do
      expect(Ai::ImprovementRecommendation::RECOMMENDATION_TYPES).to eq(
        %w[provider_switch team_composition timeout_adjustment model_upgrade cost_optimization skill_consolidation skill_connection prompt_refinement skill_creation]
      )
    end
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let(:account) { create(:account) }

    describe '.pending' do
      let!(:pending_rec) { create(:ai_improvement_recommendation, account: account, status: 'pending') }
      let!(:approved_rec) { create(:ai_improvement_recommendation, account: account, status: 'approved') }

      it 'returns only pending recommendations' do
        expect(described_class.pending).to include(pending_rec)
        expect(described_class.pending).not_to include(approved_rec)
      end
    end

    describe '.approved' do
      let!(:pending_rec) { create(:ai_improvement_recommendation, account: account, status: 'pending') }
      let!(:approved_rec) { create(:ai_improvement_recommendation, account: account, status: 'approved') }

      it 'returns only approved recommendations' do
        expect(described_class.approved).to include(approved_rec)
        expect(described_class.approved).not_to include(pending_rec)
      end
    end

    describe '.applied' do
      let!(:applied_rec) { create(:ai_improvement_recommendation, account: account, status: 'applied') }
      let!(:pending_rec) { create(:ai_improvement_recommendation, account: account, status: 'pending') }

      it 'returns only applied recommendations' do
        expect(described_class.applied).to include(applied_rec)
        expect(described_class.applied).not_to include(pending_rec)
      end
    end

    describe '.dismissed' do
      let!(:dismissed_rec) { create(:ai_improvement_recommendation, account: account, status: 'dismissed') }
      let!(:pending_rec) { create(:ai_improvement_recommendation, account: account, status: 'pending') }

      it 'returns only dismissed recommendations' do
        expect(described_class.dismissed).to include(dismissed_rec)
        expect(described_class.dismissed).not_to include(pending_rec)
      end
    end

    describe '.high_confidence' do
      let!(:high_conf) { create(:ai_improvement_recommendation, account: account, confidence_score: 0.85) }
      let!(:low_conf) { create(:ai_improvement_recommendation, account: account, confidence_score: 0.5) }
      let!(:threshold_conf) { create(:ai_improvement_recommendation, account: account, confidence_score: 0.7) }

      it 'returns recommendations with confidence_score >= 0.7' do
        expect(described_class.high_confidence).to include(high_conf, threshold_conf)
        expect(described_class.high_confidence).not_to include(low_conf)
      end
    end

    describe '.by_type' do
      let!(:provider_rec) { create(:ai_improvement_recommendation, account: account, recommendation_type: 'provider_switch') }
      let!(:cost_rec) { create(:ai_improvement_recommendation, account: account, recommendation_type: 'cost_optimization') }

      it 'returns recommendations of the specified type' do
        expect(described_class.by_type('provider_switch')).to include(provider_rec)
        expect(described_class.by_type('provider_switch')).not_to include(cost_rec)
      end
    end

    describe '.recent' do
      let!(:old_rec) { create(:ai_improvement_recommendation, account: account, created_at: 2.days.ago) }
      let!(:new_rec) { create(:ai_improvement_recommendation, account: account, created_at: 1.minute.ago) }

      it 'returns recommendations ordered by created_at desc' do
        results = described_class.recent
        expect(results.first).to eq(new_rec)
      end

      it 'defaults to 50 records' do
        expect(described_class.recent.limit_value).to eq(50)
      end

      it 'accepts a custom limit' do
        expect(described_class.recent(10).limit_value).to eq(10)
      end
    end
  end

  # ==========================================
  # Instance Methods
  # ==========================================
  describe '#approve!' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:recommendation) { create(:ai_improvement_recommendation, account: account, status: 'pending') }

    it 'updates status to approved' do
      recommendation.approve!(user)
      expect(recommendation.reload.status).to eq('approved')
    end

    it 'sets approved_by to the given user' do
      recommendation.approve!(user)
      expect(recommendation.reload.approved_by).to eq(user)
    end
  end

  describe '#apply!' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:recommendation) { create(:ai_improvement_recommendation, account: account, status: 'approved') }

    it 'updates status to applied' do
      recommendation.apply!(user)
      expect(recommendation.reload.status).to eq('applied')
    end

    it 'sets approved_by to the given user' do
      recommendation.apply!(user)
      expect(recommendation.reload.approved_by).to eq(user)
    end

    it 'sets applied_at to the current time' do
      freeze_time do
        recommendation.apply!(user)
        expect(recommendation.reload.applied_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe '#dismiss!' do
    let(:account) { create(:account) }
    let(:recommendation) { create(:ai_improvement_recommendation, account: account, status: 'pending') }

    it 'updates status to dismissed' do
      recommendation.dismiss!
      expect(recommendation.reload.status).to eq('dismissed')
    end
  end

  describe '#target' do
    let(:account) { create(:account) }
    let(:agent) { create(:ai_agent, account: account) }

    it 'returns the target object when it exists' do
      recommendation = create(:ai_improvement_recommendation,
                              account: account,
                              target_type: 'Ai::Agent',
                              target_id: agent.id)

      expect(recommendation.target).to eq(agent)
    end

    it 'returns nil when the target does not exist' do
      recommendation = create(:ai_improvement_recommendation,
                              account: account,
                              target_type: 'Ai::Agent',
                              target_id: SecureRandom.uuid)

      expect(recommendation.target).to be_nil
    end

    it 'returns nil when the target_type is an invalid class' do
      recommendation = create(:ai_improvement_recommendation,
                              account: account,
                              target_type: 'NonExistentClass',
                              target_id: SecureRandom.uuid)

      expect(recommendation.target).to be_nil
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_improvement_recommendation)).to be_valid
    end
  end
end
