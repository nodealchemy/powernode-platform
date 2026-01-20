# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::CustomerHealthScoreService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  describe "#calculate_health_score" do
    it "calculates health score for an account" do
      result = service.calculate_health_score

      expect(result).to be_a(CustomerHealthScore)
      expect(result.overall_score).to be_between(0, 100)
      expect(result.health_status).to be_present
    end

    it "stores component scores" do
      result = service.calculate_health_score

      expect(result.engagement_score).to be_present
      expect(result.payment_score).to be_present
      expect(result.usage_score).to be_present
      expect(result.support_score).to be_present
      expect(result.tenure_score).to be_present
    end

    it "sets appropriate health status based on score" do
      result = service.calculate_health_score

      expected_status = CustomerHealthScore.determine_health_status(result.overall_score)
      expect(result.health_status).to eq(expected_status)
    end

    it "sets risk level" do
      result = service.calculate_health_score

      expect(result.risk_level).to be_present
      expect(%w[none low medium high critical]).to include(result.risk_level)
    end

    it "tracks trend direction" do
      result = service.calculate_health_score

      expect(result.trend_direction).to be_present
      expect(%w[improving stable declining critical_decline]).to include(result.trend_direction)
    end

    it "identifies risk factors" do
      result = service.calculate_health_score

      expect(result.risk_factors).to be_an(Array)
    end
  end

  describe ".calculate_all_accounts" do
    let!(:accounts) { create_list(:account, 3) }

    it "calculates scores for all active accounts" do
      results = described_class.calculate_all_accounts

      expect(results[:success]).to be >= 0
      expect(results[:failed]).to be >= 0
      expect(results).to include(:errors)
    end
  end

  describe "private methods" do
    describe "#calculate_engagement_score" do
      it "returns score based on login activity" do
        # Create a user with recent login
        create(:user, account: account, last_login_at: 1.day.ago)

        score = service.send(:calculate_engagement_score, service.send(:gather_metrics))

        expect(score).to be_between(0, 100)
      end
    end

    describe "#calculate_payment_score" do
      it "returns score based on payment history" do
        score = service.send(:calculate_payment_score, service.send(:gather_metrics))

        expect(score).to be_between(0, 100)
      end
    end

    describe "#calculate_usage_score" do
      it "returns score based on usage patterns" do
        score = service.send(:calculate_usage_score, service.send(:gather_metrics))

        expect(score).to be_between(0, 100)
      end
    end

    describe "#calculate_support_score" do
      it "returns score based on support interactions" do
        score = service.send(:calculate_support_score, service.send(:gather_metrics))

        expect(score).to be_between(0, 100)
      end
    end

    describe "#calculate_tenure_score" do
      it "returns higher score for longer tenure" do
        # Account with subscription created 1 year ago
        create(:subscription, account: account)
        account.subscription.update_column(:created_at, 1.year.ago)
        account.reload

        metrics = service.send(:gather_metrics)
        score = service.send(:calculate_tenure_score, metrics)

        expect(score).to be >= 70 # Long tenure should have high score
      end
    end

    describe "#identify_risk_factors" do
      it "identifies risk factors from low scores" do
        component_scores = {
          engagement: 30,
          payment: 90,
          usage: 80,
          support: 80,
          tenure: 80
        }
        metrics = { usage_trend: "growing", subscription_age_days: 100, payment_failures_30d: 0, last_login_days_ago: 1, feature_adoption_rate: 0.5 }

        risk_factors = service.send(:identify_risk_factors, component_scores, metrics)

        expect(risk_factors).to include("Low engagement")
      end
    end
  end
end
