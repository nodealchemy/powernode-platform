# frozen_string_literal: true

module Analytics
  class CustomerHealthScoreService
    attr_reader :account

    # Component weights for overall score calculation
    WEIGHTS = {
      engagement: 0.25,
      payment: 0.30,
      usage: 0.20,
      support: 0.15,
      tenure: 0.10
    }.freeze

    def initialize(account)
      @account = account
    end

    def calculate_health_score
      metrics = gather_metrics
      component_scores = calculate_component_scores(metrics)
      overall_score = calculate_overall_score(component_scores)

      previous_score = account.customer_health_scores.latest
      trend_data = calculate_trend(overall_score, previous_score)

      health_status = CustomerHealthScore.determine_health_status(overall_score)
      risk_level = CustomerHealthScore.determine_risk_level(overall_score)
      risk_factors = identify_risk_factors(component_scores, metrics)

      CustomerHealthScore.create!(
        account: account,
        subscription: account.subscription,
        overall_score: overall_score,
        health_status: health_status,
        engagement_score: component_scores[:engagement],
        payment_score: component_scores[:payment],
        usage_score: component_scores[:usage],
        support_score: component_scores[:support],
        tenure_score: component_scores[:tenure],
        at_risk: risk_level.in?(%w[critical high medium]),
        risk_level: risk_level,
        risk_factors: risk_factors,
        score_change_30d: trend_data[:change_30d],
        score_change_90d: trend_data[:change_90d],
        trend_direction: trend_data[:direction],
        metrics_snapshot: metrics,
        component_details: component_scores,
        calculated_at: Time.current
      )
    end

    def self.calculate_all_accounts
      results = { success: 0, failed: 0, errors: [] }

      Account.active.find_each do |account|
        service = new(account)
        service.calculate_health_score
        results[:success] += 1
      rescue StandardError => e
        results[:failed] += 1
        results[:errors] << { account_id: account.id, error: e.message }
      end

      results
    end

    private

    def gather_metrics
      subscription = account.subscription
      {
        # Engagement metrics
        last_login_days_ago: calculate_last_login_days,
        active_users_ratio: calculate_active_users_ratio,
        feature_adoption_rate: calculate_feature_adoption,

        # Payment metrics
        payment_failures_30d: count_payment_failures,
        on_time_payment_rate: calculate_on_time_rate,
        outstanding_balance: calculate_outstanding_balance,

        # Usage metrics
        usage_trend: calculate_usage_trend,
        quota_utilization: calculate_quota_utilization,

        # Support metrics
        open_tickets: count_open_tickets,
        ticket_sentiment: calculate_ticket_sentiment,
        response_satisfaction: calculate_support_satisfaction,

        # Tenure metrics
        account_age_days: (Date.current - account.created_at.to_date).to_i,
        subscription_age_days: subscription ? (Date.current - subscription.created_at.to_date).to_i : 0,
        lifetime_value: calculate_ltv
      }
    end

    def calculate_component_scores(metrics)
      {
        engagement: calculate_engagement_score(metrics),
        payment: calculate_payment_score(metrics),
        usage: calculate_usage_score(metrics),
        support: calculate_support_score(metrics),
        tenure: calculate_tenure_score(metrics)
      }
    end

    def calculate_engagement_score(metrics)
      score = 100

      # Penalize for inactivity
      if metrics[:last_login_days_ago] > 30
        score -= 40
      elsif metrics[:last_login_days_ago] > 14
        score -= 20
      elsif metrics[:last_login_days_ago] > 7
        score -= 10
      end

      # Factor in active users
      score -= (1 - metrics[:active_users_ratio]) * 30

      # Factor in feature adoption
      score -= (1 - metrics[:feature_adoption_rate]) * 20

      [score, 0].max.round(2)
    end

    def calculate_payment_score(metrics)
      score = 100

      # Penalize payment failures
      score -= metrics[:payment_failures_30d] * 20

      # Factor in on-time payment rate
      score -= (1 - metrics[:on_time_payment_rate]) * 40

      # Penalize outstanding balance
      if metrics[:outstanding_balance] > 0
        score -= 20
      end

      [score, 0].max.round(2)
    end

    def calculate_usage_score(metrics)
      score = 100

      # Penalize declining usage
      if metrics[:usage_trend] == "declining"
        score -= 30
      elsif metrics[:usage_trend] == "stagnant"
        score -= 10
      end

      # Low quota utilization is a risk
      if metrics[:quota_utilization] < 0.2
        score -= 40
      elsif metrics[:quota_utilization] < 0.5
        score -= 20
      end

      [score, 0].max.round(2)
    end

    def calculate_support_score(metrics)
      score = 100

      # Open tickets reduce score
      score -= metrics[:open_tickets] * 10

      # Negative sentiment reduces score
      if metrics[:ticket_sentiment] == "negative"
        score -= 30
      elsif metrics[:ticket_sentiment] == "neutral"
        score -= 10
      end

      # Low satisfaction
      if metrics[:response_satisfaction] < 0.5
        score -= 30
      elsif metrics[:response_satisfaction] < 0.7
        score -= 15
      end

      [score, 0].max.round(2)
    end

    def calculate_tenure_score(metrics)
      # Longer tenure = higher score
      tenure_days = metrics[:subscription_age_days]

      if tenure_days >= 365
        100
      elsif tenure_days >= 180
        85
      elsif tenure_days >= 90
        70
      elsif tenure_days >= 30
        55
      else
        40
      end
    end

    def calculate_overall_score(component_scores)
      score = 0
      WEIGHTS.each do |component, weight|
        score += (component_scores[component] || 0) * weight
      end
      score.round(2)
    end

    def calculate_trend(current_score, previous_health_score)
      change_30d = nil
      change_90d = nil

      score_30d_ago = account.customer_health_scores.where("calculated_at < ?", 30.days.ago).order(calculated_at: :desc).first
      score_90d_ago = account.customer_health_scores.where("calculated_at < ?", 90.days.ago).order(calculated_at: :desc).first

      change_30d = (current_score - score_30d_ago.overall_score).round(2) if score_30d_ago
      change_90d = (current_score - score_90d_ago.overall_score).round(2) if score_90d_ago

      direction = CustomerHealthScore.determine_trend(current_score, previous_health_score&.overall_score)

      { change_30d: change_30d, change_90d: change_90d, direction: direction }
    end

    def identify_risk_factors(component_scores, metrics)
      factors = []

      factors << "Low engagement" if component_scores[:engagement] < 50
      factors << "Payment issues" if component_scores[:payment] < 50
      factors << "Declining usage" if metrics[:usage_trend] == "declining"
      factors << "Support dissatisfaction" if component_scores[:support] < 50
      factors << "Recent signup" if metrics[:subscription_age_days] < 30
      factors << "Multiple payment failures" if metrics[:payment_failures_30d] > 2
      factors << "No recent activity" if metrics[:last_login_days_ago] > 14
      factors << "Low feature adoption" if metrics[:feature_adoption_rate] < 0.3

      factors
    end

    # Metric calculation helpers (simplified implementations)
    def calculate_last_login_days
      last_login = account.users.maximum(:last_login_at)
      return 365 unless last_login
      (Date.current - last_login.to_date).to_i
    end

    def calculate_active_users_ratio
      total = account.users.count
      return 1.0 if total == 0
      active = account.users.where("last_login_at > ?", 30.days.ago).count
      (active.to_f / total).round(2)
    end

    def calculate_feature_adoption
      # Simplified - would check actual feature usage
      0.65
    end

    def count_payment_failures
      account.payments.where(status: "failed", created_at: 30.days.ago..Time.current).count
    rescue StandardError
      0
    end

    def calculate_outstanding_balance
      # Sum of unpaid invoice amounts
      account.invoices.where.not(status: "paid").sum(:total_cents) / 100.0
    rescue StandardError
      0
    end

    def calculate_on_time_rate
      total = account.invoices.where("due_at < ?", Time.current).count
      return 1.0 if total == 0
      on_time = account.invoices.where("paid_at <= due_at").count
      (on_time.to_f / total).round(2)
    rescue StandardError
      1.0
    end

    def calculate_usage_trend
      # Simplified - would analyze actual usage data
      %w[growing stagnant declining].sample
    end

    def calculate_quota_utilization
      # Simplified - would check actual quota usage
      rand(0.3..0.9).round(2)
    end

    def count_open_tickets
      # Would integrate with support system
      0
    end

    def calculate_ticket_sentiment
      # Would use sentiment analysis
      %w[positive neutral negative].sample
    end

    def calculate_support_satisfaction
      # Would check actual satisfaction scores
      rand(0.6..1.0).round(2)
    end

    def calculate_ltv
      # Simplified LTV calculation
      subscription = account.subscription
      return 0 unless subscription

      monthly_value = subscription.plan&.price_cents || 0
      tenure_months = ((Date.current - subscription.created_at.to_date) / 30.0).ceil
      ((monthly_value / 100.0) * tenure_months).round(2)
    end
  end
end
