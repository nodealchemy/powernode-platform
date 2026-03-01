# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerHealthScore, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:subscription).optional }
  end

  describe "validations" do
    subject { build(:customer_health_score, account: account) }

    it { is_expected.to validate_presence_of(:overall_score) }
    it { is_expected.to validate_presence_of(:health_status) }
    it { is_expected.to validate_presence_of(:calculated_at) }
    it { is_expected.to validate_numericality_of(:overall_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_inclusion_of(:health_status).in_array(%w[critical at_risk needs_attention healthy thriving]) }
    it { is_expected.to validate_inclusion_of(:risk_level).in_array(%w[critical high medium low none]) }
    it { is_expected.to validate_inclusion_of(:trend_direction).in_array(%w[improving stable declining critical_decline]) }
  end

  describe "status helpers" do
    describe "#critical?" do
      it "returns true when health_status is critical" do
        score = build(:customer_health_score, health_status: "critical")
        expect(score.critical?).to be true
      end

      it "returns false when health_status is not critical" do
        score = build(:customer_health_score, health_status: "healthy")
        expect(score.critical?).to be false
      end
    end

    describe "#at_risk?" do
      it "returns true when at_risk flag is set" do
        score = build(:customer_health_score, at_risk: true)
        expect(score.at_risk?).to be true
      end
    end

    describe "#healthy?" do
      it "returns true when health_status is healthy or thriving" do
        expect(build(:customer_health_score, health_status: "healthy").healthy?).to be true
        expect(build(:customer_health_score, health_status: "thriving").healthy?).to be true
      end

      it "returns false for other statuses" do
        expect(build(:customer_health_score, health_status: "critical").healthy?).to be false
      end
    end

    describe "#improving?" do
      it "returns true when trend_direction is improving" do
        score = build(:customer_health_score, trend_direction: "improving")
        expect(score.improving?).to be true
      end
    end

    describe "#declining?" do
      it "returns true when trend_direction is declining or critical_decline" do
        expect(build(:customer_health_score, trend_direction: "declining").declining?).to be true
        expect(build(:customer_health_score, trend_direction: "critical_decline").declining?).to be true
      end
    end
  end

  describe ".determine_health_status" do
    it "returns thriving for scores >= 85" do
      expect(described_class.determine_health_status(90)).to eq("thriving")
    end

    it "returns healthy for scores >= 70" do
      expect(described_class.determine_health_status(75)).to eq("healthy")
    end

    it "returns needs_attention for scores >= 50" do
      expect(described_class.determine_health_status(55)).to eq("needs_attention")
    end

    it "returns at_risk for scores >= 30" do
      expect(described_class.determine_health_status(35)).to eq("at_risk")
    end

    it "returns critical for scores < 30" do
      expect(described_class.determine_health_status(15)).to eq("critical")
    end
  end

  describe ".determine_risk_level" do
    it "returns none for scores >= 85" do
      expect(described_class.determine_risk_level(90)).to eq("none")
    end

    it "returns low for scores >= 70" do
      expect(described_class.determine_risk_level(75)).to eq("low")
    end

    it "returns medium for scores >= 50" do
      expect(described_class.determine_risk_level(55)).to eq("medium")
    end

    it "returns high for scores >= 30" do
      expect(described_class.determine_risk_level(35)).to eq("high")
    end

    it "returns critical for scores < 30" do
      expect(described_class.determine_risk_level(15)).to eq("critical")
    end
  end

  describe ".determine_trend" do
    it "returns improving when change > 10" do
      expect(described_class.determine_trend(80, 65)).to eq("improving")
    end

    it "returns stable when change between 0 and 10" do
      expect(described_class.determine_trend(80, 75)).to eq("stable")
    end

    it "returns declining when change between -10 and 0" do
      expect(described_class.determine_trend(70, 75)).to eq("declining")
    end

    it "returns critical_decline when change < -10" do
      expect(described_class.determine_trend(60, 75)).to eq("critical_decline")
    end

    it "returns stable when no previous score" do
      expect(described_class.determine_trend(80, nil)).to eq("stable")
    end
  end

  describe "#calculate_weighted_score" do
    let(:health_score) do
      build(:customer_health_score,
        engagement_score: 80,
        payment_score: 90,
        usage_score: 70,
        support_score: 75,
        tenure_score: 65
      )
    end

    it "calculates weighted score with default weights" do
      # 80*0.25 + 90*0.30 + 70*0.20 + 75*0.15 + 65*0.10 = 20 + 27 + 14 + 11.25 + 6.5 = 78.75
      expect(health_score.calculate_weighted_score).to eq(78.75)
    end

    it "accepts custom weights" do
      custom_weights = { engagement: 0.5, payment: 0.5, usage: 0, support: 0, tenure: 0 }
      # 80*0.5 + 90*0.5 = 40 + 45 = 85
      expect(health_score.calculate_weighted_score(custom_weights)).to eq(85.0)
    end
  end

  describe "#primary_risk_factor" do
    it "returns first risk factor" do
      score = build(:customer_health_score, risk_factors: [ "low_engagement", "payment_issues" ])
      expect(score.primary_risk_factor).to eq("low_engagement")
    end

    it "returns nil when no risk factors" do
      score = build(:customer_health_score, risk_factors: [])
      expect(score.primary_risk_factor).to be_nil
    end
  end

  describe "#summary" do
    let(:health_score) { create(:customer_health_score, account: account) }

    it "returns summary hash with all components" do
      summary = health_score.summary

      expect(summary).to include(:id, :account_id, :overall_score, :health_status)
      expect(summary).to include(:at_risk, :risk_level, :risk_factors, :trend_direction)
      expect(summary[:components]).to include(:engagement, :payment, :usage, :support, :tenure)
    end
  end

  describe "scopes" do
    let!(:thriving) { create(:customer_health_score, :thriving, account: account) }
    let!(:at_risk) { create(:customer_health_score, :at_risk, account: create(:account)) }
    let!(:critical) { create(:customer_health_score, :critical, account: create(:account)) }

    it "filters at_risk scores" do
      expect(described_class.at_risk).to include(at_risk, critical)
      expect(described_class.at_risk).not_to include(thriving)
    end

    it "filters healthy scores" do
      expect(described_class.healthy).to include(thriving)
      expect(described_class.healthy).not_to include(at_risk, critical)
    end

    it "filters needs_attention scores" do
      expect(described_class.needs_attention).to include(at_risk, critical)
      expect(described_class.needs_attention).not_to include(thriving)
    end

    it "orders by recent" do
      older = create(:customer_health_score, account: create(:account), calculated_at: 2.days.ago)
      newer = create(:customer_health_score, account: create(:account), calculated_at: 1.hour.from_now)

      recent = described_class.recent
      expect(recent.first).to eq(newer)
    end
  end
end
