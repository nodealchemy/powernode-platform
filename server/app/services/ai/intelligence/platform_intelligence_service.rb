# frozen_string_literal: true

module Ai
  module Intelligence
    class PlatformIntelligenceService < BaseIntelligenceService
      # =====================================================================
      # BaaS Intelligence Methods
      # =====================================================================

      # Detect anomalous BaaS usage patterns
      def usage_anomalies(tenant_id: nil)
        return success_response(anomalies: [], analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        scope = BaaS::UsageRecord.joins(:baas_tenant).where(baas_tenants: { account_id: @account.id })
        scope = scope.where(baas_tenant_id: tenant_id) if tenant_id.present?

        recent = scope.where("baas_usage_records.created_at >= ?", 24.hours.ago)
        baseline = scope.where("baas_usage_records.created_at BETWEEN ? AND ?", 7.days.ago, 24.hours.ago)

        anomalies = detect_usage_anomalies(recent, baseline)
        audit_action("baas_usage_anomalies", "BaaS::Tenant", context: { count: anomalies.size })

        success_response(anomalies: anomalies, analyzed_at: Time.current.iso8601)
      rescue StandardError => e
        error_response("usage_anomalies", e)
      end

      # Predict tenant churn from usage metrics
      def tenant_churn_prediction
        return success_response(predictions: [], high_risk_count: 0, analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        tenants = BaaS::Tenant.where(account_id: @account.id).active
        predictions = tenants.map { |t| predict_tenant_churn(t) }.compact
                             .sort_by { |p| -p[:churn_probability] }

        success_response(
          predictions: predictions,
          high_risk_count: predictions.count { |p| p[:churn_probability] > 0.7 },
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("tenant_churn_prediction", e)
      end

      # Dynamic pricing recommendations
      def pricing_recommendations
        return success_response(recommendations: [], analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        subscriptions = BaaS::Subscription.joins(:baas_tenant)
                                          .where(baas_tenants: { account_id: @account.id })
                                          .active
        recommendations = subscriptions.map { |s| analyze_pricing(s) }.compact

        success_response(recommendations: recommendations, analyzed_at: Time.current.iso8601)
      rescue StandardError => e
        error_response("pricing_recommendations", e)
      end

      # Detect API key fraud patterns
      def api_fraud_detection
        return success_response(suspicious_keys: [], total_analyzed: 0, analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        keys = BaaS::ApiKey.joins(:baas_tenant)
                           .where(baas_tenants: { account_id: @account.id })
                           .active
        suspicious = keys.select { |k| suspicious_api_usage?(k) }

        success_response(
          suspicious_keys: suspicious.map { |k| serialize_suspicious_key(k) },
          total_analyzed: keys.count,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("api_fraud_detection", e)
      end

      # =====================================================================
      # Reseller Intelligence Methods
      # =====================================================================

      # Score resellers based on referral volume, commission earnings, payout history
      def performance_scores
        return success_response(scores: [], total_resellers: 0, top_performers: [], analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        resellers = Reseller.where(account_id: @account.id).active
        scores = resellers.map { |r| score_reseller(r) }.sort_by { |s| -s[:score] }

        success_response(
          scores: scores,
          total_resellers: resellers.count,
          top_performers: scores.first(5),
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("performance_scores", e)
      end

      # Analyze commission rates vs performance, recommend adjustments
      def commission_optimization
        return success_response(recommendations: [], total_analyzed: 0, analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        resellers = Reseller.where(account_id: @account.id).active.includes(:commissions)
        recommendations = resellers.filter_map { |r| analyze_commission(r) }

        success_response(
          recommendations: recommendations.sort_by { |r| -r[:potential_impact] },
          total_analyzed: resellers.count,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("commission_optimization", e)
      end

      # Check referred accounts for churn signals
      def referral_churn_risks
        return success_response(risks: [], total_referrals: 0, high_risk_count: 0, analyzed_at: Time.current.iso8601, status: :enterprise_required) unless defined?(PowernodeEnterprise::Engine)

        referrals = ResellerReferral.joins(:reseller)
                                    .where(resellers: { account_id: @account.id })
                                    .active
                                    .includes(:referred_account, :reseller)

        risks = referrals.filter_map { |ref| assess_referral_churn(ref) }
                         .sort_by { |r| -r[:risk_score] }

        success_response(
          risks: risks,
          total_referrals: referrals.count,
          high_risk_count: risks.count { |r| r[:risk_level] == "high" },
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("referral_churn_risks", e)
      end

      private

      # --- BaaS private methods ---

      def detect_usage_anomalies(recent, baseline)
        return [] if baseline.empty?

        baseline_avg = baseline.average(:quantity)&.to_f || 0
        baseline_stddev = calculate_stddev(baseline.pluck(:quantity).map(&:to_f))
        threshold = baseline_avg + (2 * baseline_stddev)

        recent.where("baas_usage_records.quantity > ?", [threshold, 1].max).limit(50).map do |record|
          {
            record_id: record.id,
            tenant_id: record.baas_tenant_id,
            quantity: record.quantity.to_f,
            expected_max: threshold.round(2),
            deviation_factor: baseline_avg > 0 ? (record.quantity.to_f / baseline_avg).round(2) : 0,
            created_at: record.created_at.iso8601
          }
        end
      end

      def calculate_stddev(values)
        return 0 if values.empty?

        mean = values.sum / values.size.to_f
        variance = values.sum { |v| (v - mean)**2 } / values.size
        Math.sqrt(variance)
      end

      def predict_tenant_churn(tenant)
        recent_usage = tenant.usage_records.where("created_at >= ?", 30.days.ago)
        prior_usage = tenant.usage_records.where("created_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)

        recent_total = recent_usage.sum(:quantity).to_f
        prior_total = prior_usage.sum(:quantity).to_f

        decline_rate = prior_total > 0 ? (1.0 - (recent_total / prior_total)).clamp(0, 1) : 0
        days_since_last = (Time.current - (recent_usage.maximum(:created_at) || tenant.created_at)).to_f / 1.day

        churn_probability = calculate_churn_score(decline_rate, days_since_last)

        {
          tenant_id: tenant.id,
          tenant_name: tenant.name,
          churn_probability: churn_probability.round(4),
          risk_level: churn_risk_level(churn_probability),
          decline_rate: decline_rate.round(4),
          days_inactive: days_since_last.round(1),
          recent_usage: recent_total,
          prior_usage: prior_total
        }
      end

      def calculate_churn_score(decline_rate, days_inactive)
        score = (decline_rate * 0.6) + ([days_inactive / 30.0, 1.0].min * 0.4)
        score.clamp(0, 1)
      end

      def churn_risk_level(probability)
        if probability > 0.7 then "high"
        elsif probability > 0.4 then "medium"
        else "low"
        end
      end

      def analyze_pricing(subscription)
        usage = subscription.baas_tenant.usage_records
                            .where("created_at >= ?", 30.days.ago)
        total_usage = usage.sum(:quantity).to_f

        return nil if total_usage.zero?

        recommendation = if total_usage > 10_000
                           "upgrade"
                         elsif total_usage < 100
                           "downgrade"
                         else
                           "maintain"
                         end

        {
          subscription_id: subscription.id,
          tenant_id: subscription.baas_tenant_id,
          current_plan: subscription.plan_external_id,
          monthly_usage: total_usage,
          recommendation: recommendation,
          confidence: 0.75
        }
      end

      def suspicious_api_usage?(key)
        key.total_requests.to_i > key.rate_limit_per_day.to_i ||
          (key.last_used_at.present? && key.last_used_at > 1.minute.ago &&
           key.total_requests.to_i > key.rate_limit_per_minute.to_i * 60)
      end

      def serialize_suspicious_key(key)
        {
          api_key_id: key.id,
          tenant_id: key.baas_tenant_id,
          key_prefix: key.key_prefix,
          total_requests: key.total_requests,
          rate_limit_per_day: key.rate_limit_per_day,
          last_used_at: key.last_used_at&.iso8601,
          reason: "high_frequency_usage"
        }
      end

      # --- Reseller private methods ---

      def score_reseller(reseller)
        referral_count = reseller.referrals.active.count
        total_commissions = reseller.commissions.sum(:commission_amount).to_f
        paid_payouts = reseller.payouts.where(status: "completed").sum(:amount).to_f
        active_referrals = reseller.referrals.active.count

        # Score 0-100 based on weighted factors
        referral_score = [referral_count * 5, 40].min
        commission_score = [total_commissions / 100.0, 35].min
        payout_score = paid_payouts > 0 ? [paid_payouts / 200.0, 25].min : 0

        total_score = (referral_score + commission_score + payout_score).round(1)

        {
          reseller_id: reseller.id,
          company_name: reseller.company_name,
          tier: reseller.tier,
          score: total_score,
          referral_count: referral_count,
          active_referrals: active_referrals,
          total_commissions: total_commissions.round(2),
          total_payouts: paid_payouts.round(2),
          performance_tier: performance_tier(total_score)
        }
      end

      def performance_tier(score)
        if score >= 80 then "excellent"
        elsif score >= 60 then "strong"
        elsif score >= 40 then "average"
        elsif score >= 20 then "developing"
        else "underperforming"
        end
      end

      def analyze_commission(reseller)
        commissions = reseller.commissions.where("earned_at >= ?", 90.days.ago)
        return nil if commissions.empty?

        total_earned = commissions.sum(:commission_amount).to_f
        avg_rate = commissions.average(:commission_percentage)&.to_f || 0
        referral_count = reseller.referrals.active.count

        # Determine if rate adjustment is warranted
        recommendation = if referral_count >= 15 && avg_rate < 20
                           "increase"
                         elsif referral_count < 3 && avg_rate > 15
                           "decrease"
                         else
                           "maintain"
                         end

        suggested_rate = case recommendation
                         when "increase" then [avg_rate + 5, 25].min
                         when "decrease" then [avg_rate - 3, 10].max
                         else avg_rate
                         end

        potential_impact = ((suggested_rate - avg_rate) / 100.0 * total_earned).abs.round(2)

        {
          reseller_id: reseller.id,
          company_name: reseller.company_name,
          current_rate: avg_rate.round(2),
          suggested_rate: suggested_rate.round(2),
          recommendation: recommendation,
          referral_count: referral_count,
          quarterly_earnings: total_earned.round(2),
          potential_impact: potential_impact
        }
      end

      def assess_referral_churn(referral)
        account = referral.referred_account
        return nil unless account

        subscription = account.subscription
        days_since_referral = (Time.current - referral.referred_at).to_f / 1.day

        risk_score = 0.0
        risk_factors = []

        # Check subscription status
        if subscription.nil?
          risk_score += 0.4
          risk_factors << "no_active_subscription"
        elsif subscription.respond_to?(:status)
          case subscription.status
          when "past_due"
            risk_score += 0.3
            risk_factors << "past_due_subscription"
          when "canceled", "cancelled"
            risk_score += 0.5
            risk_factors << "canceled_subscription"
          end
        end

        # Check inactivity
        last_login = account.users.maximum(:last_sign_in_at)
        if last_login.nil? || last_login < 30.days.ago
          risk_score += 0.3
          risk_factors << "inactive_account"
        end

        # Early churn is more impactful
        if days_since_referral < 90
          risk_score += 0.1
          risk_factors << "early_lifecycle"
        end

        risk_score = risk_score.clamp(0, 1)
        return nil if risk_score < 0.2

        {
          referral_id: referral.id,
          reseller_id: referral.reseller_id,
          reseller_name: referral.reseller.company_name,
          referred_account_id: account.id,
          risk_score: risk_score.round(3),
          risk_level: risk_score > 0.6 ? "high" : risk_score > 0.3 ? "medium" : "low",
          risk_factors: risk_factors,
          days_since_referral: days_since_referral.round(0)
        }
      end
    end
  end
end
