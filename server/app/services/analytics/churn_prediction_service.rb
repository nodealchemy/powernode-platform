# frozen_string_literal: true

module Analytics
  class ChurnPredictionService
    MODEL_VERSION = "1.0.0"

    attr_reader :account

    # Feature weights for logistic regression approximation
    FEATURE_WEIGHTS = {
      health_score: -0.03,
      days_since_login: 0.02,
      payment_failures: 0.15,
      usage_decline_rate: 0.10,
      support_tickets_open: 0.05,
      tenure_months: -0.01,
      contract_ending_soon: 0.20,
      price_increase_recent: 0.08,
      competitor_mentions: 0.12
    }.freeze

    # Recommended actions based on risk factors
    INTERVENTION_ACTIONS = {
      "engagement_decline" => [
        { action: "schedule_success_call", priority: "high", description: "Schedule customer success call to re-engage" },
        { action: "send_feature_tips", priority: "medium", description: "Send personalized feature adoption tips" }
      ],
      "payment_issues" => [
        { action: "payment_recovery", priority: "high", description: "Initiate payment recovery workflow" },
        { action: "offer_payment_plan", priority: "medium", description: "Offer flexible payment arrangement" }
      ],
      "usage_decline" => [
        { action: "usage_review", priority: "high", description: "Review usage patterns and optimize" },
        { action: "training_session", priority: "medium", description: "Offer training or onboarding refresh" }
      ],
      "contract_ending" => [
        { action: "renewal_outreach", priority: "high", description: "Proactive renewal conversation" },
        { action: "loyalty_offer", priority: "medium", description: "Present loyalty incentive" }
      ],
      "support_issues" => [
        { action: "escalate_tickets", priority: "high", description: "Escalate open support tickets" },
        { action: "executive_sponsor", priority: "medium", description: "Assign executive sponsor" }
      ]
    }.freeze

    def initialize(account)
      @account = account
    end

    def predict
      features = extract_features
      probability = calculate_churn_probability(features)
      risk_tier = ChurnPrediction.determine_risk_tier(probability)
      contributing_factors = identify_contributing_factors(features)
      recommended_actions = generate_recommendations(contributing_factors)

      ChurnPrediction.create!(
        account: account,
        subscription: account.subscription,
        churn_probability: probability,
        risk_tier: risk_tier,
        predicted_churn_date: calculate_predicted_date(probability),
        days_until_churn: ChurnPrediction.calculate_days_until_churn(probability),
        contributing_factors: contributing_factors,
        primary_risk_factor: contributing_factors.first&.dig("factor"),
        confidence_score: calculate_confidence(features),
        model_version: MODEL_VERSION,
        prediction_type: "monthly",
        recommended_actions: recommended_actions,
        predicted_at: Time.current
      )
    end

    def self.predict_all_accounts
      results = { success: 0, failed: 0, high_risk: 0, errors: [] }

      Account.active.find_each do |account|
        service = new(account)
        prediction = service.predict

        results[:success] += 1
        results[:high_risk] += 1 if prediction.high_risk?
      rescue StandardError => e
        results[:failed] += 1
        results[:errors] << { account_id: account.id, error: e.message }
      end

      results
    end

    private

    def extract_features
      health_score = account.customer_health_scores.latest
      subscription = account.subscription

      {
        health_score: health_score&.overall_score || 50,
        days_since_login: calculate_days_since_login,
        payment_failures: count_recent_payment_failures,
        usage_decline_rate: calculate_usage_decline_rate,
        support_tickets_open: count_open_support_tickets,
        tenure_months: calculate_tenure_months,
        contract_ending_soon: contract_ending_soon?,
        price_increase_recent: recent_price_increase?,
        competitor_mentions: detect_competitor_mentions
      }
    end

    def calculate_churn_probability(features)
      # Simplified logistic regression approximation
      log_odds = 0.0

      FEATURE_WEIGHTS.each do |feature, weight|
        value = features[feature]
        value = value ? 1.0 : 0.0 if value.is_a?(TrueClass) || value.is_a?(FalseClass)
        log_odds += weight * value.to_f
      end

      # Add base bias (intercept)
      log_odds += 0.5

      # Sigmoid function
      probability = 1.0 / (1.0 + Math.exp(-log_odds))

      # Clamp between 0 and 1
      [[probability, 0.0].max, 1.0].min.round(4)
    end

    def identify_contributing_factors(features)
      factors = []

      # Low health score
      if features[:health_score] < 50
        factors << {
          factor: "engagement_decline",
          weight: 0.25,
          description: "Customer health score is low",
          value: features[:health_score]
        }
      end

      # Inactivity
      if features[:days_since_login] > 14
        factors << {
          factor: "engagement_decline",
          weight: 0.20,
          description: "No recent platform activity",
          value: features[:days_since_login]
        }
      end

      # Payment failures
      if features[:payment_failures] > 0
        factors << {
          factor: "payment_issues",
          weight: 0.30,
          description: "Recent payment failures",
          value: features[:payment_failures]
        }
      end

      # Usage decline
      if features[:usage_decline_rate] > 0.2
        factors << {
          factor: "usage_decline",
          weight: 0.20,
          description: "Declining platform usage",
          value: features[:usage_decline_rate]
        }
      end

      # Contract ending
      if features[:contract_ending_soon]
        factors << {
          factor: "contract_ending",
          weight: 0.25,
          description: "Contract ending within 30 days",
          value: true
        }
      end

      # Open tickets
      if features[:support_tickets_open] > 2
        factors << {
          factor: "support_issues",
          weight: 0.15,
          description: "Multiple open support tickets",
          value: features[:support_tickets_open]
        }
      end

      # Sort by weight descending
      factors.sort_by { |f| -f[:weight] }
    end

    def generate_recommendations(contributing_factors)
      recommendations = []

      contributing_factors.each do |factor|
        actions = INTERVENTION_ACTIONS[factor[:factor]]
        next unless actions

        actions.each do |action|
          recommendations << action.merge(
            triggered_by: factor[:factor],
            factor_description: factor[:description]
          )
        end
      end

      # Sort by priority and limit
      priority_order = { "high" => 0, "medium" => 1, "low" => 2 }
      recommendations.sort_by { |r| priority_order[r[:priority]] }.first(5)
    end

    def calculate_predicted_date(probability)
      days = ChurnPrediction.calculate_days_until_churn(probability)
      return nil unless days
      Date.current + days.days
    end

    def calculate_confidence(features)
      # Higher confidence with more data
      data_completeness = features.values.compact.size.to_f / features.size
      (data_completeness * 0.9).round(4)
    end

    # Feature extraction helpers
    def calculate_days_since_login
      last_login = account.users.maximum(:last_login_at)
      return 365 unless last_login
      (Date.current - last_login.to_date).to_i
    end

    def count_recent_payment_failures
      account.payments.where(status: "failed", created_at: 90.days.ago..Time.current).count
    rescue StandardError
      0
    end

    def calculate_usage_decline_rate
      # Simplified - would compare usage metrics over time
      rand(0.0..0.4).round(2)
    end

    def count_open_support_tickets
      # Would integrate with support system
      0
    end

    def calculate_tenure_months
      subscription = account.subscription
      return 0 unless subscription
      ((Date.current - subscription.created_at.to_date) / 30.0).ceil
    end

    def contract_ending_soon?
      subscription = account.subscription
      return false unless subscription&.current_period_end

      (subscription.current_period_end - Date.current).to_i <= 30
    end

    def recent_price_increase?
      # Would check for recent plan price changes
      false
    end

    def detect_competitor_mentions
      # Would analyze support tickets/feedback for competitor mentions
      0
    end
  end
end
