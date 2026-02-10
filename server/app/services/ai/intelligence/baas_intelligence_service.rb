# frozen_string_literal: true

module Ai
  module Intelligence
    class BaasIntelligenceService
      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Detect anomalous BaaS usage patterns
      def usage_anomalies(tenant_id: nil)
        scope = BaaS::UsageRecord.joins(:baas_tenant).where(baas_tenants: { account_id: @account.id })
        scope = scope.where(baas_tenant_id: tenant_id) if tenant_id.present?

        recent = scope.where("baas_usage_records.created_at >= ?", 24.hours.ago)
        baseline = scope.where("baas_usage_records.created_at BETWEEN ? AND ?", 7.days.ago, 24.hours.ago)

        anomalies = detect_usage_anomalies(recent, baseline)
        log_audit("usage_anomalies", anomalies.size)

        success_response(anomalies: anomalies, analyzed_at: Time.current.iso8601)
      rescue StandardError => e
        error_response("usage_anomalies", e)
      end

      # Predict tenant churn from usage metrics
      def tenant_churn_prediction
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

      private

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

      def log_audit(action, count)
        Ai::ComplianceAuditEntry.log!(
          account: @account,
          action_type: "ai_intelligence_baas_#{action}",
          resource_type: "BaaS::Tenant",
          outcome: "success",
          description: "BaaS Intelligence: #{action.humanize} (#{count} results)",
          context: { analyzed_at: Time.current }
        )
      rescue StandardError => e
        @logger.warn("[BaasIntelligence] Audit log failed: #{e.message}")
      end

      def success_response(**data) = { success: true }.merge(data)

      def error_response(method_name, exception)
        @logger.error("[Ai::Intelligence::BaasIntelligenceService##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end
    end
  end
end
