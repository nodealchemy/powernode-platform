# frozen_string_literal: true

module Ai
  module Intelligence
    class RevenueIntelligenceService
      HEALTH_STATUSES = %w[critical at_risk needs_attention healthy thriving].freeze
      RISK_TIERS = %w[critical high medium low minimal].freeze

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Analyze revenue data and generate actionable insights
      def generate_insights(period_days: 30)
        cutoff_date = period_days.days.ago.to_date
        snapshots = revenue_snapshots.where("snapshot_date >= ?", cutoff_date).order(:snapshot_date)
        return error_hash("No revenue snapshots found for the last #{period_days} days") if snapshots.empty?

        latest = snapshots.last
        earliest = snapshots.first
        growth = analyze_growth(earliest, latest, period_days)
        churn = analyze_churn_patterns(cutoff_date)
        health = current_health_distribution
        insights = compile_insights(growth, churn, health, latest)

        audit_action("generate_insights", "RevenueSnapshot", latest.id, context: { period_days: period_days })

        success_response(
          period_days: period_days, current_mrr_cents: latest.mrr_cents, current_arr_cents: latest.arr_cents,
          active_subscriptions: latest.active_subscriptions, growth_analysis: growth, churn_analysis: churn,
          health_distribution: health, revenue_concentration: analyze_revenue_concentration,
          snapshot_trend: snapshots.map { |s| { date: s.snapshot_date.iso8601, mrr_cents: s.mrr_cents, arr_cents: s.arr_cents, active_subscriptions: s.active_subscriptions, new_subscriptions: s.new_subscriptions, churned_subscriptions: s.churned_subscriptions } },
          insights: insights, generated_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("generate_insights", e)
      end

      # Aggregate churn predictions into risk report with cohorts
      def churn_risk_report
        predictions = ChurnPrediction.where(account: @account).recent.limit(1000)
        return error_hash("No churn predictions available") if predictions.empty?

        latest = dedup_predictions(predictions)
        by_tier = latest.group_by(&:risk_tier)

        tier_counts = RISK_TIERS.each_with_object({}) do |tier, h|
          preds = by_tier[tier] || []
          h[tier] = { count: preds.size, avg_probability: preds.any? ? (preds.sum(&:churn_probability) / preds.size).round(3) : 0, needs_intervention: preds.count(&:needs_intervention?) }
        end

        high_risk = latest.select(&:high_risk?)
        top_factors = aggregate_risk_factors(latest)

        interventions = []
        c = tier_counts["critical"]
        interventions << { priority: "critical", action: "immediate_outreach", description: "#{c[:needs_intervention]} critical-risk accounts need immediate personal outreach", target_tier: "critical" } if c && c[:needs_intervention] > 0
        hi = tier_counts["high"]
        interventions << { priority: "high", action: "retention_campaign", description: "Launch targeted retention campaign for #{hi[:count]} high-risk accounts", target_tier: "high" } if hi && hi[:count] > 0
        top_factors.first(3).each { |f| interventions << { priority: "medium", action: "address_risk_factor", description: "Address '#{f[:factor]}' affecting #{f[:occurrence_count]} accounts", target_factor: f[:factor] } }
        m = tier_counts["medium"]
        interventions << { priority: "low", action: "engagement_program", description: "Enroll #{m[:count]} medium-risk accounts in engagement program", target_tier: "medium" } if m && m[:count] > 5

        success_response(
          total_predictions: latest.size, risk_tier_distribution: tier_counts,
          at_risk_account_count: high_risk.size, estimated_at_risk_mrr_cents: estimate_at_risk_revenue(high_risk),
          top_risk_factors: top_factors,
          intervention_stats: { total_needing: latest.count(&:needs_intervention?), triggered: latest.count(&:intervention_triggered), pending: latest.count { |p| p.needs_intervention? && !p.intervention_triggered } },
          suggested_interventions: interventions, generated_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("churn_risk_report", e)
      end

      # Compare forecasts vs actuals and identify drift
      def forecast_accuracy_analysis
        forecasts = RevenueForecast.where(account: @account).where.not(actual_mrr: nil).order(forecast_date: :asc)
        return error_hash("No forecasts with actual data available for accuracy analysis") if forecasts.empty?

        accuracy_data = forecasts.map do |f|
          f.calculate_accuracy! unless f.accuracy_percentage.present?
          { forecast_date: f.forecast_date, forecast_type: f.forecast_type, projected_mrr: f.projected_mrr,
            actual_mrr: f.actual_mrr, accuracy_percentage: f.accuracy_percentage, variance: f.variance,
            variance_percentage: f.variance_percentage, within_confidence: f.within_confidence_interval?(f.actual_mrr) }
        end

        accuracies = accuracy_data.filter_map { |a| a[:accuracy_percentage] }
        avg_accuracy = accuracies.any? ? (accuracies.sum / accuracies.size).round(2) : nil
        within_ci = accuracy_data.count { |a| a[:within_confidence] }
        variances = accuracy_data.filter_map { |a| a[:variance] }

        pending = RevenueForecast.where(account: @account).future.where(actual_mrr: nil).order(:forecast_date).limit(12).map(&:summary)

        success_response(
          total_evaluated: accuracy_data.size, average_accuracy: avg_accuracy,
          within_confidence_interval: within_ci,
          confidence_interval_rate: accuracy_data.any? ? (within_ci.to_f / accuracy_data.size * 100).round(1) : nil,
          drift_analysis: detect_forecast_drift(variances), accuracy_trend: accuracy_trend(accuracy_data),
          historical_accuracy: accuracy_data, pending_forecasts: pending, analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("forecast_accuracy_analysis", e)
      end

      # Customer health score distribution with trend analysis
      def health_score_distribution
        scores = CustomerHealthScore.where(account: @account).recent
        return error_hash("No customer health scores available") if scores.empty?

        latest = dedup_health_scores(scores)
        status_dist = HEALTH_STATUSES.each_with_object({}) do |status, h|
          matching = latest.select { |s| s.health_status == status }
          h[status] = { count: matching.size, avg_score: matching.any? ? (matching.sum(&:overall_score) / matching.size).round(1) : 0, percentage: (matching.size.to_f / latest.size * 100).round(1) }
        end

        components = %i[engagement_score payment_score usage_score support_score tenure_score].each_with_object({}) do |comp, h|
          vals = latest.filter_map { |s| s.send(comp) }
          h[comp.to_s.delete_suffix("_score").to_sym] = vals.any? ? (vals.sum.to_f / vals.size).round(1) : 0
        end

        declining = latest.select(&:declining?)

        success_response(
          total_accounts: latest.size, overall_avg_score: (latest.sum(&:overall_score).to_f / latest.size).round(1),
          status_distribution: status_dist, component_averages: components,
          trend_distribution: latest.group_by(&:trend_direction).transform_values(&:count),
          declining_count: declining.size, improving_count: latest.count(&:improving?),
          at_risk_count: latest.count(&:at_risk?), accounts_needing_attention: declining.first(10).map(&:summary),
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("health_score_distribution", e)
      end

      # Recommend retention actions for a specific account
      def intervention_recommendations(account_id:)
        target = Account.find_by(id: account_id)
        return error_hash("Account not found: #{account_id}") unless target

        hs = CustomerHealthScore.where(account: target).recent.first
        cp = ChurnPrediction.where(account: target).recent.first
        return error_hash("No health score or churn prediction data for account #{account_id}") unless hs || cp

        snapshot = RevenueSnapshot.for_account(target).order(snapshot_date: :desc).first
        recs = build_intervention_recs(hs, cp)
        urgency = intervention_urgency(hs, cp)

        audit_action("intervention_recommendations", "Account", target.id, context: { urgency: urgency })

        success_response(
          account_id: target.id, urgency: urgency,
          risk_summary: { health_status: hs&.health_status, overall_score: hs&.overall_score, trend: hs&.trend_direction, churn_probability: cp&.churn_probability, churn_risk_tier: cp&.risk_tier, primary_risk_factor: cp&.primary_risk_factor, days_until_predicted_churn: cp&.days_until_churn },
          health_score: hs&.summary, churn_prediction: cp&.summary,
          revenue_context: snapshot ? { mrr_cents: snapshot.mrr_cents, active_subscriptions: snapshot.active_subscriptions } : nil,
          recommendations: recs, recommended_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("intervention_recommendations", e)
      end

      private

      def analyze_growth(earliest, latest, period_days)
        mrr_change = latest.mrr_cents - earliest.mrr_cents
        pct = earliest.mrr_cents > 0 ? (mrr_change.to_f / earliest.mrr_cents * 100).round(2) : 0
        net = latest.new_subscriptions - latest.churned_subscriptions
        {
          mrr_change_cents: mrr_change, mrr_growth_percentage: pct,
          annualized_growth_percentage: period_days > 0 ? (pct * 365.0 / period_days).round(2) : 0,
          subscription_change: latest.active_subscriptions - earliest.active_subscriptions,
          new_subscriptions: latest.new_subscriptions, churned_subscriptions: latest.churned_subscriptions,
          net_subscription_growth: net, arpu_cents: latest.arpu_cents,
          growth_trajectory: pct > 5 ? "accelerating" : pct > 0 ? "growing" : pct > -5 ? "stagnating" : "declining"
        }
      end

      def analyze_churn_patterns(cutoff_date)
        preds = ChurnPrediction.where(account: @account).where("predicted_at >= ?", cutoff_date)
        return { available: false } if preds.empty?
        { available: true, average_churn_probability: preds.average(:churn_probability)&.round(3),
          high_risk_count: preds.high_risk.count, tier_breakdown: preds.group(:risk_tier).count,
          intervention_rate: preds.where(intervention_triggered: true).count.to_f / [preds.count, 1].max }
      end

      def analyze_revenue_concentration
        latest = revenue_snapshots.order(snapshot_date: :desc).first
        return nil unless latest && latest.active_subscriptions > 0 && latest.mrr_cents > 0
        active = latest.active_subscriptions
        { arpu_cents: latest.arpu_cents, active_subscriptions: active,
          concentration_risk: active < 10 ? "high" : active < 50 ? "medium" : "low",
          description: "Revenue #{active < 10 ? 'concentrated across' : 'distributed across'} #{active} subscriptions" }
      end

      def compile_insights(growth, churn, health, latest)
        insights = []
        pct = growth[:mrr_growth_percentage]
        insights << { type: "growth", severity: "positive", title: "Strong MRR growth", description: "MRR grew #{pct}% in the analysis period", metric: pct } if pct > 10
        insights << { type: "growth", severity: "warning", title: "MRR declining", description: "MRR decreased #{pct.abs}% - investigate causes", metric: pct } if pct < -5
        insights << { type: "churn", severity: "warning", title: "High-risk accounts detected", description: "#{churn[:high_risk_count]} accounts at high churn risk", metric: churn[:high_risk_count] } if churn[:available] && churn[:high_risk_count].to_i > 0

        if health.present?
          ar = health.dig("at_risk", :percentage).to_f + health.dig("critical", :percentage).to_f
          insights << { type: "health", severity: "critical", title: "High proportion of at-risk customers", description: "#{ar.round(1)}% of customers are at-risk or critical", metric: ar.round(1) } if ar > 20
        end

        net = growth[:net_subscription_growth].to_i
        insights << { type: "subscriptions", severity: "warning", title: "Net subscription loss", description: "Losing more subscriptions than gaining (net: #{net})", metric: net } if net < 0
        insights << { type: "revenue", severity: "info", title: "Low ARPU", description: "Average revenue per user is low - consider upsell strategies", metric: latest.arpu_cents } if latest.arpu_cents > 0 && latest.arpu_cents < 500
        insights.sort_by { |i| %w[critical warning info positive].index(i[:severity]) || 99 }
      end

      def current_health_distribution
        scores = CustomerHealthScore.where(account: @account).recent.limit(500)
        latest = dedup_health_scores(scores)
        return {} if latest.empty?
        HEALTH_STATUSES.each_with_object({}) do |status, h|
          m = latest.count { |s| s.health_status == status }
          h[status] = { count: m, percentage: (m.to_f / latest.size * 100).round(1) }
        end
      end

      def dedup_predictions(predictions)
        predictions.group_by(&:account_id).map { |_, p| p.min_by { |x| -x.predicted_at.to_i } }
      end

      def dedup_health_scores(scores)
        scores.group_by(&:account_id).map { |_, g| g.min_by { |s| -s.calculated_at.to_i } }
      end

      def estimate_at_risk_revenue(high_risk)
        ids = high_risk.map(&:account_id).uniq
        return 0 if ids.empty?
        RevenueSnapshot.where(account_id: ids).select("DISTINCT ON (account_id) account_id, mrr_cents").order(:account_id, snapshot_date: :desc).sum(&:mrr_cents)
      rescue StandardError
        0
      end

      def aggregate_risk_factors(predictions)
        counts = Hash.new(0)
        predictions.each do |p|
          counts[p.primary_risk_factor] += 1 if p.primary_risk_factor.present?
          p.contributing_factors&.each { |f| name = f.is_a?(Hash) ? (f["name"] || f["factor"]) : f.to_s; counts[name] += 1 if name.present? }
        end
        counts.sort_by { |_, v| -v }.first(10).map { |f, c| { factor: f, occurrence_count: c, percentage: (c.to_f / predictions.size * 100).round(1) } }
      end

      def detect_forecast_drift(variances)
        return { detected: false, direction: "neutral" } if variances.size < 3
        pos = variances.count { |v| v > 0 }
        neg = variances.count { |v| v < 0 }
        avg = (variances.sum.to_f / variances.size).round(2)
        if pos > variances.size * 0.7
          { detected: true, direction: "under_predicting", avg_variance: avg, description: "Forecasts consistently under-predict actuals by an average of #{avg.abs}" }
        elsif neg > variances.size * 0.7
          { detected: true, direction: "over_predicting", avg_variance: avg, description: "Forecasts consistently over-predict actuals by an average of #{avg.abs}" }
        else
          { detected: false, direction: "neutral", avg_variance: avg, description: "Forecasts show no significant directional bias" }
        end
      end

      def accuracy_trend(data)
        return "insufficient_data" if data.size < 4
        half = data.size / 2
        earlier = data.first(half).filter_map { |a| a[:accuracy_percentage] }
        later = data.last(half).filter_map { |a| a[:accuracy_percentage] }
        return "insufficient_data" if earlier.empty? || later.empty?
        diff = later.sum / later.size - earlier.sum / earlier.size
        diff > 3 ? "improving" : diff < -3 ? "degrading" : "stable"
      end

      def build_intervention_recs(hs, cp)
        recs = []
        if hs
          recs << { type: "engagement", priority: "high", action: "Schedule product walkthrough or training session", reason: "Low engagement score (#{hs.engagement_score})" } if hs.engagement_score.to_i < 40
          recs << { type: "billing", priority: "high", action: "Review billing issues - potential payment failures or disputes", reason: "Low payment score (#{hs.payment_score})" } if hs.payment_score.to_i < 40
          recs << { type: "adoption", priority: "medium", action: "Send feature adoption guides and usage tips", reason: "Low usage score (#{hs.usage_score})" } if hs.usage_score.to_i < 40
          recs << { type: "support", priority: "medium", action: "Proactive support check-in - review open tickets and satisfaction", reason: "Low support score (#{hs.support_score})" } if hs.support_score.to_i < 40
          recs << { type: "trend", priority: "high", action: "Executive sponsor outreach - health trending downward", reason: "Health trend: #{hs.trend_direction}" } if hs.declining?
        end
        if cp
          recs << { type: "retention", priority: "critical", action: "Immediate executive outreach with retention offer", reason: "Critical churn risk (#{cp.probability_percentage}%)" } if cp.critical_risk?
          recs << { type: "retention", priority: "high", action: "Schedule success review meeting within 48 hours", reason: "High churn risk (#{cp.probability_percentage}%)" } if !cp.critical_risk? && cp.high_risk?
          cp.recommended_actions&.each do |a|
            text = a.is_a?(Hash) ? (a["description"] || a["action"]) : a.to_s
            recs << { type: "model_recommendation", priority: "medium", action: text, reason: "AI churn model recommendation" } if text.present?
          end
          recs << { type: "intervention", priority: "high", action: "Trigger automated intervention workflow", reason: "Intervention threshold met but not yet triggered" } if cp.needs_intervention? && !cp.intervention_triggered
        end
        recs << { type: "maintenance", priority: "low", action: "Continue regular account health monitoring", reason: "No immediate risk indicators detected" } if recs.empty?
        recs.sort_by { |r| %w[critical high medium low].index(r[:priority]) || 99 }
      end

      def intervention_urgency(hs, cp)
        score = 0
        if hs
          score += 3 if hs.critical?
          score += 2 if hs.at_risk?
          score += 2 if hs.declining?
        end
        if cp
          score += 3 if cp.critical_risk?
          score += 2 if cp.high_risk?
          score += 1 if cp.needs_intervention?
        end
        score >= 5 ? "critical" : score >= 3 ? "high" : score >= 1 ? "medium" : "low"
      end

      def revenue_snapshots = RevenueSnapshot.for_account(@account)

      def audit_action(action, resource_type, resource_id, context: {})
        Ai::ComplianceAuditEntry.log!(account: @account, action_type: "ai_intelligence_#{action}", resource_type: resource_type, resource_id: resource_id, outcome: "success", description: "AI Intelligence: #{action.humanize}", context: context)
      rescue StandardError => e
        @logger.warn("Failed to log audit entry for #{action}: #{e.message}")
      end

      def success_response(**data) = { success: true }.merge(data)

      def error_response(method_name, exception)
        @logger.error("[Ai::Intelligence::RevenueIntelligenceService##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end

      def error_hash(message) = { success: false, error: message }
    end
  end
end
