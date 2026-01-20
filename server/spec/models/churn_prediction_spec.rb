# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChurnPrediction, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:subscription).optional }
  end

  describe "validations" do
    subject { build(:churn_prediction, account: account) }

    it { is_expected.to validate_presence_of(:churn_probability) }
    it { is_expected.to validate_presence_of(:risk_tier) }
    it { is_expected.to validate_presence_of(:model_version) }
    it { is_expected.to validate_presence_of(:predicted_at) }
    it { is_expected.to validate_numericality_of(:churn_probability).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1) }
    it { is_expected.to validate_inclusion_of(:risk_tier).in_array(%w[critical high medium low minimal]) }
    it { is_expected.to validate_inclusion_of(:prediction_type).in_array(%w[weekly monthly quarterly]) }
  end

  describe "#probability_percentage" do
    it "returns probability as percentage" do
      prediction = build(:churn_prediction, churn_probability: 0.75)
      expect(prediction.probability_percentage).to eq(75.0)
    end
  end

  describe "#critical_risk?" do
    it "returns true for critical tier" do
      prediction = build(:churn_prediction, risk_tier: "critical")
      expect(prediction.critical_risk?).to be true
    end

    it "returns false for other tiers" do
      prediction = build(:churn_prediction, risk_tier: "high")
      expect(prediction.critical_risk?).to be false
    end
  end

  describe "#high_risk?" do
    it "returns true for critical tier" do
      prediction = build(:churn_prediction, risk_tier: "critical")
      expect(prediction.high_risk?).to be true
    end

    it "returns true for high tier" do
      prediction = build(:churn_prediction, risk_tier: "high")
      expect(prediction.high_risk?).to be true
    end

    it "returns false for lower tiers" do
      prediction = build(:churn_prediction, risk_tier: "medium")
      expect(prediction.high_risk?).to be false
    end
  end

  describe "#needs_intervention?" do
    it "returns true when high risk and no intervention triggered" do
      prediction = build(:churn_prediction, risk_tier: "high", intervention_triggered: false)
      expect(prediction.needs_intervention?).to be true
    end

    it "returns false when intervention already triggered" do
      prediction = build(:churn_prediction, risk_tier: "high", intervention_triggered: true)
      expect(prediction.needs_intervention?).to be false
    end

    it "returns false for low risk" do
      prediction = build(:churn_prediction, risk_tier: "low", intervention_triggered: false)
      expect(prediction.needs_intervention?).to be false
    end
  end

  describe "#trigger_intervention!" do
    let(:prediction) { create(:churn_prediction, :high_risk, account: account) }

    it "sets intervention_triggered to true" do
      prediction.trigger_intervention!
      expect(prediction.intervention_triggered).to be true
    end

    it "sets intervention_at timestamp" do
      prediction.trigger_intervention!
      expect(prediction.intervention_at).to be_present
    end
  end

  describe "#top_contributing_factors" do
    let(:prediction) do
      build(:churn_prediction,
        contributing_factors: [
          { "factor" => "a", "weight" => 0.1 },
          { "factor" => "b", "weight" => 0.4 },
          { "factor" => "c", "weight" => 0.3 },
          { "factor" => "d", "weight" => 0.2 }
        ]
      )
    end

    it "returns factors sorted by weight descending" do
      factors = prediction.top_contributing_factors
      expect(factors.first["factor"]).to eq("b")
      expect(factors.second["factor"]).to eq("c")
    end

    it "limits results" do
      factors = prediction.top_contributing_factors(2)
      expect(factors.length).to eq(2)
    end

    it "returns empty array when no factors" do
      prediction = build(:churn_prediction, contributing_factors: [])
      expect(prediction.top_contributing_factors).to eq([])
    end
  end

  describe ".determine_risk_tier" do
    it "returns critical for probability >= 0.80" do
      expect(described_class.determine_risk_tier(0.85)).to eq("critical")
    end

    it "returns high for probability >= 0.60" do
      expect(described_class.determine_risk_tier(0.65)).to eq("high")
    end

    it "returns medium for probability >= 0.40" do
      expect(described_class.determine_risk_tier(0.45)).to eq("medium")
    end

    it "returns low for probability >= 0.20" do
      expect(described_class.determine_risk_tier(0.25)).to eq("low")
    end

    it "returns minimal for probability < 0.20" do
      expect(described_class.determine_risk_tier(0.10)).to eq("minimal")
    end
  end

  describe ".calculate_days_until_churn" do
    it "returns nil for low probability" do
      expect(described_class.calculate_days_until_churn(0.15)).to be_nil
    end

    it "returns fewer days for higher probability" do
      high_prob_days = described_class.calculate_days_until_churn(0.8)
      low_prob_days = described_class.calculate_days_until_churn(0.3)
      expect(high_prob_days).to be < low_prob_days
    end

    it "returns at least 7 days" do
      expect(described_class.calculate_days_until_churn(0.99)).to be >= 7
    end
  end

  describe "#summary" do
    let(:prediction) { create(:churn_prediction, account: account) }

    it "returns summary hash" do
      summary = prediction.summary

      expect(summary).to include(:id, :account_id, :churn_probability, :risk_tier)
      expect(summary).to include(:probability_percentage, :predicted_churn_date, :days_until_churn)
      expect(summary).to include(:confidence_score, :recommended_actions, :intervention_triggered)
    end
  end

  describe "scopes" do
    let!(:critical) { create(:churn_prediction, :critical_risk, account: account) }
    let!(:high) { create(:churn_prediction, :high_risk, account: create(:account)) }
    let!(:low) { create(:churn_prediction, :low_risk, account: create(:account)) }

    it "filters high_risk predictions" do
      expect(described_class.high_risk).to include(critical, high)
      expect(described_class.high_risk).not_to include(low)
    end

    it "filters needs_intervention predictions" do
      expect(described_class.needs_intervention).to include(critical, high)

      critical.trigger_intervention!
      expect(described_class.needs_intervention).not_to include(critical)
    end

    it "orders by recent" do
      older = create(:churn_prediction, account: create(:account), predicted_at: 2.days.ago)
      newer = create(:churn_prediction, account: create(:account), predicted_at: 1.hour.from_now)

      recent = described_class.recent
      expect(recent.first).to eq(newer)
    end
  end
end
