# frozen_string_literal: true

module Analytics
  class AlertService
    METRIC_CALCULATORS = {
      "mrr" => -> { calculate_mrr },
      "arr" => -> { calculate_mrr * 12 },
      "churn_rate" => -> { calculate_churn_rate },
      "customer_count" => -> { Subscription.active.count },
      "active_subscriptions" => -> { Subscription.active.count },
      "new_customers" => -> { Subscription.where("started_at >= ?", 30.days.ago).count },
      "churned_customers" => -> { Subscription.where("cancelled_at >= ?", 30.days.ago).count },
      "revenue_growth" => -> { calculate_revenue_growth },
      "payment_failures" => -> { Payment.where(status: "failed", created_at: 24.hours.ago..Time.current).count },
      "arpu" => -> { calculate_arpu },
      "ltv" => -> { calculate_ltv },
      "trial_conversion" => -> { calculate_trial_conversion }
    }.freeze

    class << self
      # Check all enabled alerts
      def check_all_alerts
        results = { checked: 0, triggered: 0, errors: [] }

        AnalyticsAlert.due_for_check.not_in_cooldown.find_each do |alert|
          check_alert(alert)
          results[:checked] += 1
          results[:triggered] += 1 if alert.triggered?
        rescue StandardError => e
          results[:errors] << { alert_id: alert.id, error: e.message }
        end

        results
      end

      # Check a specific alert
      def check_alert(alert)
        return false unless alert.can_trigger?

        value = calculate_metric(alert.metric_name, alert.account)
        alert.evaluate!(value)
      end

      # Create a new alert
      def create_alert(params)
        alert = AnalyticsAlert.new(
          name: params[:name],
          alert_type: params[:alert_type] || "threshold",
          metric_name: params[:metric_name],
          condition: params[:condition],
          threshold_value: params[:threshold_value],
          account: params[:account],
          comparison_period: params[:comparison_period] || "previous_period",
          notification_channels: params[:notification_channels] || %w[email],
          notification_settings: params[:notification_settings] || {},
          cooldown_minutes: params[:cooldown_minutes] || 60,
          auto_resolve: params[:auto_resolve] != false,
          metadata: params[:metadata] || {}
        )

        if alert.save
          { success: true, alert: alert }
        else
          { success: false, errors: alert.errors.full_messages }
        end
      end

      # Get alert recommendations based on account data
      def recommend_alerts(account = nil)
        recommendations = []

        # MRR drop alert
        recommendations << {
          name: "MRR Drop Alert",
          metric_name: "mrr",
          condition: "change_percent",
          threshold_value: -10,
          description: "Alert when MRR drops by more than 10%"
        }

        # Churn spike alert
        recommendations << {
          name: "Churn Spike Alert",
          metric_name: "churn_rate",
          condition: "greater_than",
          threshold_value: 5,
          description: "Alert when monthly churn exceeds 5%"
        }

        # Payment failure alert
        recommendations << {
          name: "Payment Failure Alert",
          metric_name: "payment_failures",
          condition: "greater_than",
          threshold_value: 10,
          description: "Alert when payment failures exceed 10 in 24 hours"
        }

        # Trial conversion drop
        recommendations << {
          name: "Trial Conversion Drop",
          metric_name: "trial_conversion",
          condition: "less_than",
          threshold_value: 20,
          description: "Alert when trial conversion falls below 20%"
        }

        recommendations
      end

      # Get alert summary
      def summary
        {
          total_alerts: AnalyticsAlert.count,
          enabled: AnalyticsAlert.enabled.count,
          triggered: AnalyticsAlert.triggered.count,
          recent_events: AnalyticsAlertEvent.recent.limit(10).map(&:summary),
          unacknowledged: AnalyticsAlertEvent.unacknowledged.count,
          by_metric: AnalyticsAlert.group(:metric_name).count
        }
      end

      private

      def calculate_metric(metric_name, account = nil)
        calculator = METRIC_CALCULATORS[metric_name]
        return nil unless calculator

        calculator.call
      end

      def calculate_mrr
        Subscription.active.joins(:plan).sum("plans.price_cents")
      end

      def calculate_churn_rate
        total = Subscription.where("started_at < ?", 30.days.ago).count
        return 0 if total == 0

        churned = Subscription.where(cancelled_at: 30.days.ago..Time.current).count
        (churned.to_f / total * 100).round(2)
      end

      def calculate_revenue_growth
        current = Subscription.active.joins(:plan).sum("plans.price_cents")
        previous = RevenueSnapshot.order(snapshot_date: :desc).offset(1).first&.mrr || current
        return 0 if previous == 0

        ((current - previous) / previous * 100).round(2)
      end

      def calculate_arpu
        total_revenue = Subscription.active.joins(:plan).sum("plans.price_cents")
        total_customers = Subscription.active.count
        return 0 if total_customers == 0

        (total_revenue / total_customers).round(2)
      end

      def calculate_ltv
        arpu = calculate_arpu
        churn_rate = calculate_churn_rate / 100.0
        return 0 if churn_rate == 0

        (arpu / churn_rate).round(2)
      end

      def calculate_trial_conversion
        # Trials that started and ended in the last 60 days
        total_trials = Subscription.where(status: "trialing").where("trial_end < ?", Time.current).count
        return 0 if total_trials == 0

        converted = Subscription.where(status: "active").where("trial_end < ?", Time.current).count
        (converted.to_f / total_trials * 100).round(2)
      end
    end
  end
end
