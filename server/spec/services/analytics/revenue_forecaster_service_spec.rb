# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::RevenueForecasterService, type: :service do
  let(:service) { described_class.new }

  describe "#generate_forecast" do
    context "platform-wide forecast" do
      it "generates monthly forecasts" do
        result = service.generate_forecast(months_ahead: 3, period: :monthly)

        expect(result.count).to eq(3)
        result.each do |forecast|
          expect(forecast).to be_a(RevenueForecast)
          expect(forecast.forecast_period).to eq("monthly")
        end
      end

      it "generates forecasts for specified months ahead" do
        result = service.generate_forecast(months_ahead: 6, period: :monthly)

        expect(result.count).to eq(6)
      end

      it "includes projected MRR and ARR" do
        result = service.generate_forecast(months_ahead: 1, period: :monthly)

        forecast = result.first
        expect(forecast.projected_mrr).to be_present
        expect(forecast.projected_arr).to eq(forecast.projected_mrr * 12)
      end

      it "includes revenue projections" do
        result = service.generate_forecast(months_ahead: 1, period: :monthly)

        forecast = result.first
        expect(forecast.projected_new_revenue).to be_present
        expect(forecast.projected_expansion_revenue).to be_present
        expect(forecast.projected_churned_revenue).to be_present
        expect(forecast.projected_net_revenue).to be_present
      end

      it "includes customer projections" do
        result = service.generate_forecast(months_ahead: 1, period: :monthly)

        forecast = result.first
        expect(forecast.projected_new_customers).to be_present
        expect(forecast.projected_churned_customers).to be_present
        expect(forecast.projected_total_customers).to be_present
      end

      it "includes confidence intervals" do
        result = service.generate_forecast(months_ahead: 1, period: :monthly)

        forecast = result.first
        expect(forecast.confidence_level).to be_between(70, 95)
        expect(forecast.lower_bound).to be <= forecast.projected_mrr
        expect(forecast.upper_bound).to be >= forecast.projected_mrr
      end

      it "includes assumptions" do
        result = service.generate_forecast(months_ahead: 1, period: :monthly)

        forecast = result.first
        expect(forecast.assumptions).to include(
          "growth_rate",
          "churn_rate",
          "expansion_rate"
        )
      end
    end

    context "account-specific forecast" do
      let(:account) { create(:account) }
      let(:service) { described_class.new(account) }

      it "generates forecast for specific account" do
        result = service.generate_forecast(months_ahead: 3, period: :monthly)

        result.each do |forecast|
          expect(forecast.account).to eq(account)
        end
      end
    end
  end

  describe ".generate_platform_forecast" do
    it "generates platform-wide forecasts" do
      result = described_class.generate_platform_forecast(months_ahead: 3)

      expect(result.count).to eq(3)
      result.each do |forecast|
        expect(forecast.account).to be_nil
      end
    end
  end

  describe ".update_actuals" do
    let!(:forecast) { create(:revenue_forecast, forecast_date: Date.current.beginning_of_month) }

    it "updates forecasts with actual values" do
      described_class.update_actuals(forecast.forecast_date)

      forecast.reload
      expect(forecast.actual_mrr).to be_present
    end
  end

  describe "private methods" do
    describe "#gather_historical_data" do
      it "returns historical data" do
        data = service.send(:gather_historical_data)

        expect(data).to include(
          :current_mrr,
          :current_arr,
          :total_customers,
          :mrr_history,
          :churn_rate,
          :growth_rate,
          :expansion_rate,
          :new_customer_rate
        )
      end
    end

    describe "#analyze_trends" do
      it "analyzes revenue trends" do
        data = { mrr_history: [ { date: 3.months.ago, mrr: 10_000 }, { date: 2.months.ago, mrr: 11_000 }, { date: 1.month.ago, mrr: 12_000 } ] }

        trends = service.send(:analyze_trends, data)

        expect(trends).to include(:direction, :rate)
        expect(%w[growing stable declining]).to include(trends[:direction])
      end
    end

    describe "#detect_seasonality" do
      it "returns seasonality data" do
        seasonality = service.send(:detect_seasonality, {})

        expect(seasonality).to include(:has_seasonality, :peak_months, :low_months, :seasonal_factor)
      end
    end

    describe "#calculate_current_mrr" do
      it "returns current MRR" do
        mrr = service.send(:calculate_current_mrr)

        expect(mrr).to be >= 0
      end
    end
  end
end
