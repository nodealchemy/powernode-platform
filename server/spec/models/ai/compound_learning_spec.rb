# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CompoundLearning, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:team) { create(:ai_agent_team, account: account) }

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:ai_agent_team).class_name("Ai::AgentTeam").optional }
    it { should belong_to(:source_agent).class_name("Ai::Agent").optional }
    it { should belong_to(:source_execution).class_name("Ai::TeamExecution").optional }
    it { should belong_to(:superseded_by).class_name("Ai::CompoundLearning").optional }
    it { should belong_to(:verified_by).class_name("User").optional }
    it { should belong_to(:disproven_by).class_name("User").optional }
    it { should have_many(:superseding).class_name("Ai::CompoundLearning") }
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  describe "validations" do
    it { should validate_presence_of(:category) }
    it { should validate_presence_of(:content) }
    it { should validate_inclusion_of(:category).in_array(described_class::CATEGORIES) }
    it { should validate_inclusion_of(:scope).in_array(described_class::SCOPES) }
    it { should validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  # ============================================================================
  # VERIFY / DISPROVE
  # ============================================================================

  describe "#verify!" do
    let(:learning) { create(:ai_compound_learning, account: account, ai_agent_team: team) }

    it "sets status to verified with user association" do
      learning.verify!(user: user)
      learning.reload

      expect(learning.status).to eq("verified")
      expect(learning.verified_at).to be_within(2.seconds).of(Time.current)
      expect(learning.verified_by).to eq(user)
      expect(learning.verified_by_id).to eq(user.id)
    end

    it "boosts importance and confidence scores" do
      original_importance = learning.importance_score
      original_confidence = learning.confidence_score

      learning.verify!(user: user)
      learning.reload

      expect(learning.importance_score).to be > original_importance
      expect(learning.confidence_score).to be > original_confidence
    end
  end

  describe "#disprove!" do
    let(:learning) { create(:ai_compound_learning, account: account, ai_agent_team: team,
                            importance_score: 0.8, confidence_score: 0.8) }

    it "sets status to disproven with user association and reason" do
      learning.disprove!(user: user, reason: "Contradicted by production data")
      learning.reload

      expect(learning.status).to eq("disproven")
      expect(learning.disproven_at).to be_within(2.seconds).of(Time.current)
      expect(learning.disproven_by).to eq(user)
      expect(learning.disproven_by_id).to eq(user.id)
      expect(learning.contradiction_note).to eq("Contradicted by production data")
    end

    it "tanks importance and confidence scores" do
      learning.disprove!(user: user, reason: "Wrong")
      learning.reload

      expect(learning.importance_score).to eq(0.05)
      expect(learning.confidence_score).to eq(0.1)
    end
  end

  # ============================================================================
  # DECAY & EFFECTIVENESS
  # ============================================================================

  describe "#decay_importance!" do
    it "decays importance based on age and decay_rate" do
      learning = create(:ai_compound_learning, account: account, ai_agent_team: team,
                        importance_score: 1.0, decay_rate: 0.1,
                        updated_at: 10.days.ago)

      learning.decay_importance!
      learning.reload

      expect(learning.importance_score).to be < 0.5
      expect(learning.importance_score).to be > 0.05
    end

    it "floors importance at 0.05" do
      learning = create(:ai_compound_learning, account: account, ai_agent_team: team,
                        importance_score: 0.1, decay_rate: 0.5,
                        updated_at: 30.days.ago)

      learning.decay_importance!
      learning.reload

      expect(learning.importance_score).to eq(0.05)
    end

    it "skips decay when decay_rate is zero" do
      learning = create(:ai_compound_learning, account: account, ai_agent_team: team,
                        importance_score: 0.8, decay_rate: 0.0,
                        updated_at: 30.days.ago)

      learning.decay_importance!
      learning.reload

      expect(learning.importance_score).to eq(0.8)
    end
  end

  describe "#effective_importance" do
    it "returns raw importance when injection_count < 5" do
      learning = create(:ai_compound_learning, account: account, ai_agent_team: team,
                        importance_score: 0.7, injection_count: 3)

      expect(learning.effective_importance).to eq(0.7)
    end

    it "blends importance with effectiveness when injection_count >= 5" do
      learning = create(:ai_compound_learning, account: account, ai_agent_team: team,
                        importance_score: 0.5, injection_count: 10,
                        positive_outcome_count: 8)

      result = learning.effective_importance
      expect(result).to be > 0.5
      expect(result).to be <= 1.0
    end
  end

  describe "#record_injection_outcome!" do
    let(:learning) { create(:ai_compound_learning, account: account, ai_agent_team: team) }

    it "increments counters on success" do
      learning.record_injection_outcome!(successful: true)
      learning.reload

      expect(learning.injection_count).to eq(1)
      expect(learning.positive_outcome_count).to eq(1)
      expect(learning.negative_outcome_count).to eq(0)
      expect(learning.last_injected_at).to be_within(2.seconds).of(Time.current)
    end

    it "increments counters on failure" do
      learning.record_injection_outcome!(successful: false)
      learning.reload

      expect(learning.injection_count).to eq(1)
      expect(learning.positive_outcome_count).to eq(0)
      expect(learning.negative_outcome_count).to eq(1)
    end
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  describe "scopes" do
    let!(:active_learning) { create(:ai_compound_learning, account: account, ai_agent_team: team) }
    let!(:verified_learning) { create(:ai_compound_learning, account: account, ai_agent_team: team, status: "verified") }
    let!(:deprecated_learning) { create(:ai_compound_learning, :deprecated, account: account, ai_agent_team: team) }

    describe ".active" do
      it "returns only active learnings" do
        expect(described_class.active).to include(active_learning)
        expect(described_class.active).not_to include(verified_learning, deprecated_learning)
      end
    end

    describe ".verified" do
      it "returns only verified learnings" do
        expect(described_class.verified).to include(verified_learning)
        expect(described_class.verified).not_to include(active_learning)
      end
    end

    describe ".high_importance" do
      it "returns learnings with importance >= 0.7" do
        high = create(:ai_compound_learning, :high_importance, account: account, ai_agent_team: team)
        low = create(:ai_compound_learning, :low_importance, account: account, ai_agent_team: team)

        expect(described_class.high_importance).to include(high)
        expect(described_class.high_importance).not_to include(low)
      end
    end
  end
end
