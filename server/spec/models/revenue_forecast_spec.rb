# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevenueForecast, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account).optional }
  end

  describe "validations" do
    subject { build(:revenue_forecast) }

    it { is_expected.to validate_presence_of(:forecast_date) }
    it { is_expected.to validate_presence_of(:forecast_type) }
    it { is_expected.to validate_presence_of(:forecast_period) }
    it { is_expected.to validate_presence_of(:generated_at) }
    it { is_expected.to validate_inclusion_of(:forecast_type).in_array(%w[mrr arr customers revenue]) }
    it { is_expected.to validate_inclusion_of(:forecast_period).in_array(%w[weekly monthly quarterly yearly]) }
  end

  describe "#platform_wide?" do
    it "returns true when no account" do
      forecast = build(:revenue_forecast, account: nil)
      expect(forecast.platform_wide?).to be true
    end

    it "returns false when account is present" do
      forecast = build(:revenue_forecast, account: account)
      expect(forecast.platform_wide?).to be false
    end
  end

  describe "#has_actuals?" do
    it "returns true when actual_mrr is present" do
      forecast = build(:revenue_forecast, actual_mrr: 48000)
      expect(forecast.has_actuals?).to be true
    end

    it "returns false when actual_mrr is nil" do
      forecast = build(:revenue_forecast, actual_mrr: nil)
      expect(forecast.has_actuals?).to be false
    end
  end

  describe "#calculate_accuracy!" do
    let(:forecast) { create(:revenue_forecast, projected_mrr: 50000, actual_mrr: 48000) }

    it "calculates accuracy percentage" do
      forecast.calculate_accuracy!
      expect(forecast.accuracy_percentage).to eq(96.0)
    end

    it "does not calculate when no actuals" do
      forecast = create(:revenue_forecast, projected_mrr: 50000, actual_mrr: nil)
      forecast.calculate_accuracy!
      expect(forecast.accuracy_percentage).to be_nil
    end
  end

  describe "#within_confidence_interval?" do
    let(:forecast) { build(:revenue_forecast, lower_bound: 45000, upper_bound: 55000) }

    it "returns true when value is within bounds" do
      expect(forecast.within_confidence_interval?(50000)).to be true
    end

    it "returns false when value is below lower bound" do
      expect(forecast.within_confidence_interval?(40000)).to be false
    end

    it "returns false when value is above upper bound" do
      expect(forecast.within_confidence_interval?(60000)).to be false
    end
  end

  describe "#variance" do
    it "returns difference between actual and projected" do
      forecast = build(:revenue_forecast, projected_mrr: 50000, actual_mrr: 48000)
      expect(forecast.variance).to eq(-2000)
    end

    it "returns nil when no actuals" do
      forecast = build(:revenue_forecast, actual_mrr: nil)
      expect(forecast.variance).to be_nil
    end
  end

  describe "#variance_percentage" do
    it "returns percentage difference" do
      forecast = build(:revenue_forecast, projected_mrr: 50000, actual_mrr: 48000)
      expect(forecast.variance_percentage).to eq(-4.0)
    end

    it "returns nil when no actuals" do
      forecast = build(:revenue_forecast, actual_mrr: nil)
      expect(forecast.variance_percentage).to be_nil
    end
  end

  describe "#net_growth" do
    it "calculates net growth from revenue components" do
      forecast = build(:revenue_forecast,
        projected_new_revenue: 5000,
        projected_expansion_revenue: 3000,
        projected_churned_revenue: 2000
      )
      expect(forecast.net_growth).to eq(6000)
    end
  end

  describe "#customer_growth" do
    it "calculates net customer growth" do
      forecast = build(:revenue_forecast,
        projected_new_customers: 10,
        projected_churned_customers: 2
      )
      expect(forecast.customer_growth).to eq(8)
    end
  end

  describe "#summary" do
    let(:forecast) { create(:revenue_forecast) }

    it "returns summary hash" do
      summary = forecast.summary

      expect(summary).to include(:id, :forecast_date, :forecast_type, :forecast_period)
      expect(summary[:projections]).to include(:mrr, :arr, :new_revenue)
      expect(summary[:customers]).to include(:projected_new, :projected_churned, :projected_total)
      expect(summary[:confidence]).to include(:level, :lower_bound, :upper_bound)
    end
  end

  describe "scopes" do
    let!(:monthly) { create(:revenue_forecast, forecast_period: "monthly", forecast_date: 1.month.from_now) }
    let!(:quarterly) { create(:revenue_forecast, forecast_period: "quarterly", forecast_date: 3.months.from_now) }
    let!(:past) { create(:revenue_forecast, forecast_period: "monthly", forecast_date: 1.month.ago) }

    it "filters by period" do
      expect(described_class.by_period("monthly")).to include(monthly, past)
      expect(described_class.by_period("quarterly")).to include(quarterly)
    end

    it "filters future forecasts" do
      future = described_class.future
      expect(future).to include(monthly, quarterly)
      expect(future).not_to include(past)
    end

    it "filters past forecasts" do
      past_forecasts = described_class.past
      expect(past_forecasts).to include(past)
      expect(past_forecasts).not_to include(monthly, quarterly)
    end

    it "orders by recent" do
      recent = described_class.recent
      expect(recent.first.generated_at).to be >= recent.last.generated_at
    end
  end

  describe "platform-wide forecasts" do
    let!(:platform_forecast) { create(:revenue_forecast, account: nil) }
    let!(:account_forecast) { create(:revenue_forecast, account: account) }

    it "identifies platform-wide forecasts" do
      expect(described_class.platform_wide).to include(platform_forecast)
      expect(described_class.platform_wide).not_to include(account_forecast)
    end

    it "identifies account-specific forecasts" do
      expect(described_class.for_account(account.id)).to include(account_forecast)
    end
  end
end
