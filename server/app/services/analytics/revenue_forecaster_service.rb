# frozen_string_literal: true

module Analytics
  class RevenueForecasterService
    MODEL_VERSION = "1.0.0"

    attr_reader :account

    # Forecast periods
    PERIODS = {
      weekly: 7,
      monthly: 30,
      quarterly: 90,
      yearly: 365
    }.freeze

    def initialize(account = nil)
      @account = account
    end

    # Generate forecasts for specified number of months ahead
    def generate_forecast(months_ahead: 12, period: :monthly)
      historical_data = gather_historical_data
      trends = analyze_trends(historical_data)
      seasonality = detect_seasonality(historical_data)

      forecasts = []
      base_date = Date.current.beginning_of_month

      months_ahead.times do |i|
        forecast_date = base_date + i.months
        projection = project_revenue(
          historical_data,
          trends,
          seasonality,
          forecast_date,
          i
        )

        forecast = RevenueForecast.create!(
          account: account,
          forecast_date: forecast_date,
          forecast_type: "mrr",
          forecast_period: period.to_s,
          projected_mrr: projection[:mrr],
          projected_arr: projection[:mrr] * 12,
          projected_new_revenue: projection[:new_revenue],
          projected_expansion_revenue: projection[:expansion_revenue],
          projected_churned_revenue: projection[:churned_revenue],
          projected_net_revenue: projection[:net_revenue],
          projected_new_customers: projection[:new_customers],
          projected_churned_customers: projection[:churned_customers],
          projected_total_customers: projection[:total_customers],
          lower_bound: projection[:lower_bound],
          upper_bound: projection[:upper_bound],
          confidence_level: projection[:confidence_level],
          model_version: MODEL_VERSION,
          assumptions: projection[:assumptions],
          contributing_factors: projection[:factors],
          generated_at: Time.current
        )

        forecasts << forecast
      end

      forecasts
    end

    # Generate platform-wide forecast
    def self.generate_platform_forecast(months_ahead: 12)
      service = new(nil) # nil account = platform-wide
      service.generate_forecast(months_ahead: months_ahead)
    end

    # Update forecasts with actual values
    def self.update_actuals(forecast_date)
      forecasts = RevenueForecast.where(forecast_date: forecast_date)

      forecasts.each do |forecast|
        actual_mrr = calculate_actual_mrr(forecast.account, forecast_date)
        forecast.update!(actual_mrr: actual_mrr)
        forecast.calculate_accuracy!
      end
    end

    private

    def gather_historical_data
      snapshots = RevenueSnapshot.order(snapshot_date: :desc).limit(24)

      total_customers = if account
                          account.subscription&.status&.in?(%w[active trialing]) ? 1 : 0
      else
                          Subscription.active.count
      end

      {
        current_mrr: calculate_current_mrr,
        current_arr: calculate_current_mrr * 12,
        total_customers: total_customers,
        mrr_history: snapshots.map { |s| { date: s.snapshot_date, mrr: s.mrr, customers: s.total_subscribers } },
        churn_rate: calculate_churn_rate,
        growth_rate: calculate_growth_rate,
        expansion_rate: calculate_expansion_rate,
        new_customer_rate: calculate_new_customer_rate
      }
    end

    def analyze_trends(data)
      mrr_history = data[:mrr_history]
      return { direction: "stable", rate: 0 } if mrr_history.size < 3

      # Simple linear regression for trend
      values = mrr_history.map { |h| h[:mrr] || 0 }
      avg_change = values.each_cons(2).map { |a, b| b - a }.sum / (values.size - 1).to_f

      direction = if avg_change > 100
                    "growing"
      elsif avg_change < -100
                    "declining"
      else
                    "stable"
      end

      { direction: direction, rate: avg_change.round(2) }
    end

    def detect_seasonality(_data)
      # Simplified - would use time series analysis
      {
        has_seasonality: false,
        peak_months: [],
        low_months: [],
        seasonal_factor: 1.0
      }
    end

    def project_revenue(historical_data, trends, seasonality, forecast_date, months_out)
      current_mrr = historical_data[:current_mrr]
      growth_rate = historical_data[:growth_rate]
      churn_rate = historical_data[:churn_rate]
      expansion_rate = historical_data[:expansion_rate]
      new_customer_rate = historical_data[:new_customer_rate]

      # Apply compound growth with churn and expansion
      projected_mrr = current_mrr
      months_out.times do
        new_revenue = projected_mrr * new_customer_rate
        expansion_revenue = projected_mrr * expansion_rate
        churned_revenue = projected_mrr * churn_rate
        projected_mrr = projected_mrr + new_revenue + expansion_revenue - churned_revenue
      end

      # Apply trend adjustment
      trend_adjustment = trends[:rate] * months_out
      projected_mrr += trend_adjustment

      # Apply seasonality
      seasonal_factor = seasonality[:seasonal_factor]
      if seasonality[:peak_months].include?(forecast_date.month)
        seasonal_factor = 1.1
      elsif seasonality[:low_months].include?(forecast_date.month)
        seasonal_factor = 0.9
      end
      projected_mrr *= seasonal_factor

      # Calculate confidence interval (wider for further forecasts)
      confidence_level = 95 - (months_out * 2) # Confidence decreases over time
      confidence_level = [ confidence_level, 70 ].max

      variance = projected_mrr * (0.05 + months_out * 0.02) # Variance increases over time
      lower_bound = projected_mrr - variance
      upper_bound = projected_mrr + variance

      # Customer projections
      total_customers = historical_data[:total_customers]
      new_customers = (total_customers * new_customer_rate * (months_out + 1)).round
      churned_customers = (total_customers * churn_rate * (months_out + 1)).round
      projected_customers = total_customers + new_customers - churned_customers

      {
        mrr: projected_mrr.round(2),
        new_revenue: (projected_mrr * new_customer_rate).round(2),
        expansion_revenue: (projected_mrr * expansion_rate).round(2),
        churned_revenue: (projected_mrr * churn_rate).round(2),
        net_revenue: (projected_mrr - current_mrr).round(2),
        new_customers: new_customers,
        churned_customers: churned_customers,
        total_customers: projected_customers,
        lower_bound: lower_bound.round(2),
        upper_bound: upper_bound.round(2),
        confidence_level: confidence_level,
        assumptions: {
          growth_rate: growth_rate,
          churn_rate: churn_rate,
          expansion_rate: expansion_rate,
          trend_direction: trends[:direction],
          seasonal_factor: seasonal_factor
        },
        factors: [
          { factor: "Historical growth", impact: growth_rate },
          { factor: "Churn rate", impact: -churn_rate },
          { factor: "Expansion", impact: expansion_rate }
        ]
      }
    end

    def calculate_current_mrr
      if account
        account.subscription&.plan&.price || 0
      else
        Subscription.active.joins(:plan).sum("plans.price_cents")
      end
    end

    def calculate_churn_rate
      # Monthly churn rate (simplified)
      0.03 # 3% monthly churn
    end

    def calculate_growth_rate
      # Monthly growth rate (simplified)
      0.05 # 5% monthly growth
    end

    def calculate_expansion_rate
      # Monthly expansion revenue rate
      0.02 # 2% expansion
    end

    def calculate_new_customer_rate
      # New customer acquisition rate
      0.08 # 8% new customers per month
    end

    def self.calculate_actual_mrr(account, date)
      if account
        # For specific account
        snapshot = account.subscription
        snapshot&.plan&.price || 0
      else
        # Platform-wide
        snapshot = RevenueSnapshot.find_by(snapshot_date: date)
        snapshot&.mrr || 0
      end
    end
  end
end
