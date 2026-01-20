# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::ChurnPredictionService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  describe "#predict" do
    it "generates churn prediction for an account" do
      result = service.predict

      expect(result).to be_a(ChurnPrediction)
      expect(result.churn_probability).to be_between(0, 1)
      expect(result.risk_tier).to be_present
    end

    it "assigns correct risk tier based on probability" do
      result = service.predict

      expected_tier = case result.churn_probability
                      when 0...0.10 then "minimal"
                      when 0.10...0.25 then "low"
                      when 0.25...0.50 then "medium"
                      when 0.50...0.75 then "high"
                      else "critical"
                      end

      expect(result.risk_tier).to eq(expected_tier)
    end

    it "includes confidence score" do
      result = service.predict

      expect(result.confidence_score).to be_between(0, 1)
    end

    it "includes contributing factors" do
      result = service.predict

      expect(result.contributing_factors).to be_an(Array)
    end
  end

  describe ".predict_all_accounts" do
    let!(:accounts) { create_list(:account, 3) }

    it "generates predictions for all active accounts" do
      results = described_class.predict_all_accounts

      expect(results[:success]).to be >= 0
      expect(results).to include(:success, :failed, :high_risk, :errors)
    end
  end

  describe "private methods" do
    describe "#extract_features" do
      it "returns relevant features for the model" do
        features = service.send(:extract_features)

        expect(features).to include(
          :health_score,
          :days_since_login,
          :payment_failures,
          :usage_decline_rate,
          :support_tickets_open,
          :tenure_months,
          :contract_ending_soon,
          :price_increase_recent,
          :competitor_mentions
        )
      end
    end

    describe "#calculate_churn_probability" do
      it "returns probability between 0 and 1" do
        features = service.send(:extract_features)
        probability = service.send(:calculate_churn_probability, features)

        expect(probability).to be_between(0, 1)
      end
    end

    describe "#identify_contributing_factors" do
      it "identifies relevant churn factors" do
        features = service.send(:extract_features)
        factors = service.send(:identify_contributing_factors, features)

        expect(factors).to be_an(Array)
        factors.each do |factor|
          expect(factor).to include(:factor, :weight, :description)
        end
      end
    end

    describe "#generate_recommendations" do
      it "generates actions based on factors" do
        factors = [{ factor: "usage_decline", weight: 0.4, description: "Test" }]
        recommendations = service.send(:generate_recommendations, factors)

        expect(recommendations).to be_an(Array)
        if recommendations.any?
          expect(recommendations.first).to include(:action, :priority, :description)
        end
      end
    end
  end
end
