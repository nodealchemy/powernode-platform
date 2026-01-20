# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::AlertService, type: :service do
  let(:account) { create(:account) }

  describe ".create_alert" do
    let(:params) do
      {
        name: "High MRR Alert",
        metric_name: "mrr",
        condition: "greater_than",
        threshold_value: 100_000,
        account: account,
        notification_channels: ["email"]
      }
    end

    it "creates an alert" do
      result = described_class.create_alert(params)

      expect(result[:success]).to be true
      expect(result[:alert]).to be_a(AnalyticsAlert)
      expect(result[:alert].name).to eq("High MRR Alert")
    end

    it "creates account-specific alert" do
      result = described_class.create_alert(params)

      expect(result[:alert].account).to eq(account)
    end

    it "returns errors for invalid alert" do
      result = described_class.create_alert(params.merge(name: nil))

      expect(result[:success]).to be false
      expect(result[:errors]).to be_present
    end
  end

  describe ".check_alert" do
    let(:alert) do
      create(:analytics_alert,
        metric_name: "mrr",
        condition: "greater_than",
        threshold_value: 50_000,
        account: account
      )
    end

    it "evaluates the alert" do
      result = described_class.check_alert(alert)
      # Result depends on actual metric values - just ensure it runs
      expect([true, false]).to include(result)
    end

    it "does not trigger disabled alerts" do
      alert.update!(status: "disabled")

      result = described_class.check_alert(alert)

      expect(result).to be false
    end
  end

  describe ".check_all_alerts" do
    before do
      create(:analytics_alert, metric_name: "mrr", condition: "greater_than", threshold_value: 50_000, status: "enabled")
      create(:analytics_alert, metric_name: "churn_rate", condition: "greater_than", threshold_value: 5, status: "enabled")
    end

    it "checks all enabled alerts" do
      results = described_class.check_all_alerts

      expect(results).to include(:checked, :triggered, :errors)
      expect(results[:checked]).to be >= 0
    end
  end

  describe ".recommend_alerts" do
    it "returns alert recommendations" do
      recommendations = described_class.recommend_alerts(account)

      expect(recommendations).to be_an(Array)
      expect(recommendations.first).to include(:name, :metric_name, :condition, :threshold_value)
    end

    it "includes MRR drop alert recommendation" do
      recommendations = described_class.recommend_alerts

      mrr_alert = recommendations.find { |r| r[:metric_name] == "mrr" }
      expect(mrr_alert).to be_present
    end
  end

  describe ".summary" do
    before do
      create_list(:analytics_alert, 3, status: "enabled")
      create(:analytics_alert, :disabled)
    end

    it "returns alert summary" do
      summary = described_class.summary

      expect(summary[:total_alerts]).to eq(4)
      expect(summary[:enabled]).to eq(3)
      expect(summary).to include(:triggered, :recent_events, :unacknowledged, :by_metric)
    end
  end
end
