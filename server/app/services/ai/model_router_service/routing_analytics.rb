# frozen_string_literal: true

module Ai
  class ModelRouterService
    module RoutingAnalytics
      extend ActiveSupport::Concern

      # ── inc6: escalation audit surface + benefit measurement ────────────────
      # An "escalation" is a governed tier decision (Ai::Routing::TaskTierResolver)
      # whose persisted rationale marks decision == "escalate" — the model tier was
      # raised above the agent's baseline. The controlled benefit comparison holds
      # complexity level FIXED (from the linked Ai::TaskComplexityAssessment) and
      # compares escalated selections against standard-tier selections of the same
      # complexity.
      ESCALATION_DECISION_LABEL = "escalate"
      ESCALATED_MODEL_TIERS = %w[reasoning frontier].freeze
      HIGH_EFFORT_LEVELS = %w[xhigh max].freeze
      # Below this many escalated decisions WITH a recorded outcome, we never advise
      # tightening — the sample is too small to conclude escalation isn't paying off.
      BENEFIT_ADVISORY_MIN_DECISIONS = 10
      MAX_ESCALATION_ROWS = 200

      # Analyze potential cost savings
      def analyze_cost_savings(time_range: 30.days)
        decisions = Ai::RoutingDecision.for_account(@account)
                                        .where("created_at >= ?", time_range.ago)
                                        .where.not(actual_cost_usd: nil)

        return nil if decisions.empty?

        total_actual_cost = decisions.sum(:actual_cost_usd)
        total_alternative_cost = decisions.sum(:alternative_cost_usd)
        total_savings = decisions.sum(:savings_usd)

        {
          period_days: (time_range / 1.day).to_i,
          total_decisions: decisions.count,
          total_actual_cost_usd: total_actual_cost.to_f.round(4),
          total_alternative_cost_usd: total_alternative_cost.to_f.round(4),
          total_savings_usd: total_savings.to_f.round(4),
          savings_percentage: total_alternative_cost > 0 ?
            ((total_savings / total_alternative_cost) * 100).round(2) : 0,
          avg_savings_per_request: decisions.count > 0 ?
            (total_savings / decisions.count).to_f.round(6) : 0,
          by_strategy: decisions.group(:strategy_used).sum(:savings_usd),
          by_provider: decisions.group(:selected_provider_id)
                                .sum(:savings_usd)
                                .transform_keys { |id| Ai::Provider.find_by(id: id)&.name || id }
        }
      end

      # Get optimization recommendations
      def get_optimization_recommendations
        recommendations = []

        # Analyze recent routing decisions
        recent_decisions = Ai::RoutingDecision.for_account(@account)
                                               .recent(7.days)
                                               .where.not(actual_cost_usd: nil)

        return recommendations if recent_decisions.count < 10

        # High-cost provider recommendation
        provider_costs = recent_decisions.group(:selected_provider_id)
                                          .sum(:actual_cost_usd)
                                          .sort_by { |_, cost| -cost }

        if provider_costs.length > 1
          expensive_provider_id, expensive_cost = provider_costs.first
          expensive_provider = Ai::Provider.find_by(id: expensive_provider_id)

          if expensive_provider && expensive_cost > provider_costs.values.sum * 0.5
            recommendations << {
              type: "cost_optimization",
              priority: "high",
              title: "High concentration on expensive provider",
              description: "#{expensive_provider.name} accounts for >50% of costs",
              potential_savings_percentage: 20,
              action: "Consider enabling cost_optimized routing strategy"
            }
          end
        end

        # Latency optimization
        slow_decisions = recent_decisions.where("actual_latency_ms > ?", 5000)
        if slow_decisions.count > recent_decisions.count * 0.2
          recommendations << {
            type: "performance_optimization",
            priority: "medium",
            title: "High latency detected",
            description: "#{(slow_decisions.count.to_f / recent_decisions.count * 100).round(1)}% of requests have latency > 5s",
            action: "Consider latency_optimized or hybrid routing strategy"
          }
        end

        # Quality issues
        failed_decisions = recent_decisions.where(outcome: %w[failed timeout error])
        if failed_decisions.count > recent_decisions.count * 0.05
          recommendations << {
            type: "reliability_improvement",
            priority: "high",
            title: "High failure rate",
            description: "#{(failed_decisions.count.to_f / recent_decisions.count * 100).round(1)}% failure rate",
            action: "Review provider health and consider quality_optimized routing"
          }
        end

        recommendations
      end

      # Get routing statistics
      def statistics(time_range: 24.hours)
        Ai::RoutingDecision.stats_for_period(account: @account, period: time_range)
      end

      # Get provider performance rankings
      def provider_rankings
        providers = @account.ai_providers.active

        providers.map do |provider|
          recent_decisions = Ai::RoutingDecision.for_account(@account)
                                                 .for_provider(provider)
                                                 .recent(7.days)

          total = recent_decisions.count
          successful = recent_decisions.successful.count
          avg_cost = recent_decisions.average(:actual_cost_usd)&.to_f || 0
          avg_latency = recent_decisions.average(:actual_latency_ms)&.to_f || 0

          {
            provider_id: provider.id,
            provider_name: provider.name,
            total_requests: total,
            success_rate: total > 0 ? (successful.to_f / total * 100).round(2) : 100,
            avg_cost_usd: avg_cost.round(6),
            avg_latency_ms: avg_latency.round(2),
            score: calculate_provider_score(provider, total, successful, avg_cost, avg_latency)
          }
        end.sort_by { |p| -p[:score] }
      end

      # ── inc6 (a1): recent escalation decisions ──────────────────────────────
      # Escalation-marked RoutingDecisions, newest first, filterable by delivered
      # tier (frontier/reasoning) and time window. Reads model/tier/effort/rationale
      # off the row's jsonb (no association iteration ⇒ no N+1).
      def escalation_decisions(time_range: 7.days, tier: nil, limit: 50)
        scope = escalation_scope(time_range: time_range)
        if tier.present? && ESCALATED_MODEL_TIERS.include?(tier.to_s)
          scope = scope.where(model_tier: tier.to_s)
        end
        capped = [ [ limit.to_i, 1 ].max, MAX_ESCALATION_ROWS ].min
        scope.order(created_at: :desc).limit(capped).map { |d| escalation_summary(d) }
      end

      # ── inc6 (a2): "why did we escalate/use Fable this window" rollup ────────
      # Selection counts, top rationale categories, escalated spend share, and the
      # embedded benefit summary + advisory.
      def escalation_rollup(time_range: 7.days)
        window = window_scope(time_range: time_range)
        escalated = escalation_scope(time_range: time_range)
        benefit = escalation_benefit_deltas(time_range: time_range)

        total_spend = window.where.not(actual_cost_usd: nil).sum(:actual_cost_usd).to_f
        escalated_spend = escalated.where.not(actual_cost_usd: nil).sum(:actual_cost_usd).to_f

        {
          period_days: (time_range / 1.day).to_i,
          total_decisions: window.count,
          escalated_decisions: escalated.count,
          selections: {
            frontier: window.where(model_tier: "frontier").count,
            reasoning: window.where(model_tier: "reasoning").count,
            high_effort: window.where("rationale->>'effort' IN (?)", HIGH_EFFORT_LEVELS).count
          },
          top_rationale_categories: {
            by_complexity_level: jsonb_group_count(escalated, "rationale->'complexity'->>'level'"),
            by_task_type: jsonb_group_count(escalated, "rationale->'complexity'->>'task_type'"),
            by_decision_kind: jsonb_group_count(window, "rationale->>'decision'")
          },
          spend: {
            total_usd: total_spend.round(6),
            escalated_usd: escalated_spend.round(6),
            escalated_share_pct: total_spend > 0 ? (escalated_spend / total_spend * 100).round(2) : 0.0
          },
          benefit: benefit[:summary],
          advisory: benefit[:advisory]
        }
      end

      # ── inc6 (b2/b3): escalated-vs-baseline benefit deltas + advisory ────────
      # Controlled comparison: bucket governed decisions by [task_type,
      # complexity_level] (complexity from the LINKED assessment — the controlled
      # variable), then within each bucket compare the escalated cohort against the
      # standard-tier cohort (held/effort-substituted/downgraded to standard) on
      # success rate, avg cost, avg latency. The advisory fires when the escalated
      # cohort shows non-positive benefit at scale.
      def escalation_benefit_deltas(time_range: 7.days, task_type: nil)
        decisions = ::Ai::RoutingDecision.for_account(@account)
                                         .where("created_at >= ?", time_range.ago)
                                         .where.not(complexity_assessment_id: nil)
                                         .includes(:complexity_assessment)
                                         .to_a
                                         .select { |d| d.complexity_assessment.present? }
        if task_type.present?
          decisions = decisions.select { |d| d.complexity_assessment.task_type == task_type }
        end

        buckets = build_benefit_buckets(decisions)
        summary = summarize_benefit(buckets)
        { task_type_filter: task_type, buckets: buckets.map { |b| b[:public] }, summary: summary,
          advisory: benefit_advisory(summary) }
      end

      private

      def record_routing_decision(provider:, request_context:, matching_rule:, scoring_details:, start_time:)
        Ai::RoutingDecision.create!(
          account: @account,
          routing_rule: matching_rule,
          selected_provider: provider,
          agent_execution_id: request_context[:agent_execution_id],
          request_type: request_context[:request_type] || "completion",
          request_metadata: request_context.except(:exclude_providers),
          estimated_tokens: request_context[:estimated_tokens],
          strategy_used: @strategy,
          candidates_evaluated: scoring_details[:candidates],
          scoring_breakdown: scoring_details[:breakdown],
          decision_reason: "Selected based on #{@strategy} strategy",
          estimated_cost_usd: scoring_details[:estimated_cost_usd],
          alternative_cost_usd: calculate_alternative_cost(scoring_details[:candidates], provider.id)
        )
      end

      def calculate_alternative_cost(candidates, selected_id)
        alternatives = candidates.reject { |c| c[:provider_id] == selected_id }
        # Estimated DOLLAR cost of the most expensive alternative (savings_usd baseline).
        # Use estimated_cost, NOT the 0–1 composite routing score.
        costs = alternatives.filter_map { |c| c[:estimated_cost] }
        return nil if costs.empty?

        costs.max
      end

      def record_provider_metrics(provider, result)
        Ai::ProviderMetric.record_metrics(
          provider: provider,
          account: @account,
          metrics_data: {
            requests: 1,
            successes: result[:success] ? 1 : 0,
            failures: result[:success] ? 0 : 1,
            input_tokens: result[:input_tokens] || 0,
            output_tokens: result[:output_tokens] || 0,
            cost_usd: result[:cost_usd] || 0,
            latency_ms: result[:latency_ms],
            error_type: result[:error]&.class&.name,
            model_name: result[:model_name]
          }
        )
      end

      # ── inc6 escalation helpers ─────────────────────────────────────────────

      def window_scope(time_range:)
        ::Ai::RoutingDecision.for_account(@account).where("created_at >= ?", time_range.ago)
      end

      def escalation_scope(time_range:)
        window_scope(time_range: time_range)
          .where("rationale->>'decision' = ?", ESCALATION_DECISION_LABEL)
      end

      # Group a relation by a jsonb path expression, dropping the NULL bucket (rows
      # from the non-governed routing path carry no rationale.decision).
      def jsonb_group_count(scope, path_sql)
        scope.group(Arel.sql(path_sql)).count.reject { |k, _| k.nil? }
      end

      def escalation_summary(decision)
        rationale = decision.rationale || {}
        complexity = rationale["complexity"] || {}
        metadata = decision.request_metadata || {}
        {
          id: decision.id,
          created_at: decision.created_at,
          model_tier: decision.model_tier,
          delivered_model: rationale["delivered_model"],
          baseline_tier: rationale["baseline_tier"],
          effort: rationale["effort"],
          task_type: complexity["task_type"],
          complexity_level: complexity["level"],
          complexity_score: complexity["score"],
          agent_id: metadata["agent_id"],
          agent_type: metadata["agent_type"],
          rationale_summary: rationale["summary"] || decision.decision_reason,
          top_signals: complexity["top_signals"] || [],
          outcome: decision.outcome,
          cost_usd: decision.actual_cost_usd&.to_f,
          latency_ms: decision.actual_latency_ms,
          latency_seam: rationale["latency_seam"],
          tokens_used: decision.actual_tokens_used,
          quality_score: decision.quality_score&.to_f
        }
      end

      # One bucket per [task_type, complexity_level] that contains at least one
      # escalated decision. Carries a :public hash (returned to callers) and the raw
      # cohort members (used to re-pool the summary over matched buckets).
      def build_benefit_buckets(decisions)
        grouped = decisions.group_by do |d|
          [ d.complexity_assessment.task_type, d.complexity_assessment.complexity_level ]
        end

        grouped.filter_map do |(task_type, level), members|
          escalated = members.select { |d| (d.rationale || {})["decision"] == ESCALATION_DECISION_LABEL }
          next if escalated.empty?

          standard = members.select { |d| d.model_tier == "standard" }
          esc_stats = cohort_stats(escalated)
          std_stats = cohort_stats(standard)
          matched = esc_stats[:measured].positive? && std_stats[:measured].positive?

          {
            escalated: escalated, standard: standard, matched: matched,
            public: {
              task_type: task_type,
              complexity_level: level,
              escalated: esc_stats,
              standard: std_stats,
              matched: matched,
              deltas: cohort_deltas(esc_stats, std_stats)
            }
          }
        end
      end

      # Success rate (over outcome-recorded decisions only), avg cost, avg latency.
      # nil where there is nothing to measure — never a divide-by-zero. Latency is
      # SEGMENTED by recording seam (rationale.latency_seam — semantics differ per
      # seam, e.g. execution duration vs whole-iteration duration) and never pooled
      # across seams; untagged legacy rows fall into the "unknown" seam.
      def cohort_stats(decisions)
        measured = decisions.select { |d| d.outcome.present? }
        succeeded = measured.count { |d| d.outcome == "succeeded" }
        costs = decisions.filter_map { |d| d.actual_cost_usd&.to_f }

        {
          decisions: decisions.size,
          measured: measured.size,
          success_rate: measured.any? ? (succeeded.to_f / measured.size * 100).round(2) : nil,
          avg_cost_usd: costs.any? ? (costs.sum / costs.size).round(6) : nil,
          avg_latency_ms_by_seam: avg_latency_by_seam(decisions)
        }
      end

      def avg_latency_by_seam(decisions)
        decisions
          .select(&:actual_latency_ms)
          .group_by { |d| (d.rationale || {})["latency_seam"].presence || "unknown" }
          .transform_values { |ds| (ds.sum(&:actual_latency_ms).to_f / ds.size).round(2) }
      end

      def cohort_deltas(esc, std)
        {
          success_rate: paired_delta(esc[:success_rate], std[:success_rate], 2),
          avg_cost_usd: paired_delta(esc[:avg_cost_usd], std[:avg_cost_usd], 6),
          avg_latency_ms_by_seam: seam_latency_deltas(esc, std)
        }
      end

      # Per-seam latency deltas over the seams present in BOTH cohorts — a
      # cross-seam comparison would mix measurement semantics.
      def seam_latency_deltas(esc, std)
        esc_by_seam = esc[:avg_latency_ms_by_seam] || {}
        std_by_seam = std[:avg_latency_ms_by_seam] || {}
        (esc_by_seam.keys & std_by_seam.keys).to_h do |seam|
          [ seam, paired_delta(esc_by_seam[seam], std_by_seam[seam], 2) ]
        end
      end

      def paired_delta(escalated_value, standard_value, precision)
        return nil if escalated_value.nil? || standard_value.nil?

        (escalated_value - standard_value).round(precision)
      end

      # Pool the escalated and standard cohorts across MATCHED buckets only (both
      # sides measured) so the aggregate delta stays a controlled comparison.
      def summarize_benefit(buckets)
        matched = buckets.select { |b| b[:matched] }
        esc = matched.flat_map { |b| b[:escalated] }
        std = matched.flat_map { |b| b[:standard] }
        esc_stats = cohort_stats(esc)
        std_stats = cohort_stats(std)

        {
          matched_buckets: matched.size,
          total_buckets: buckets.size,
          escalated_measured: esc_stats[:measured],
          standard_measured: std_stats[:measured],
          escalated_success_rate: esc_stats[:success_rate],
          standard_success_rate: std_stats[:success_rate],
          success_rate_delta: paired_delta(esc_stats[:success_rate], std_stats[:success_rate], 2),
          avg_cost_delta: paired_delta(esc_stats[:avg_cost_usd], std_stats[:avg_cost_usd], 6),
          avg_latency_delta_by_seam: seam_latency_deltas(esc_stats, std_stats)
        }
      end

      # Advisory (report-only, never auto-tunes): recommend tightening escalation
      # thresholds when the escalated cohort is large enough AND shows a non-positive
      # controlled success-rate delta. Statuses distinguish "no benefit" from the
      # under-sampled / uncomparable cases so a small window never triggers a false
      # alarm.
      def benefit_advisory(summary)
        measured = summary[:escalated_measured].to_i
        delta = summary[:success_rate_delta]

        status =
          if summary[:total_buckets].to_i.zero?
            "no_escalations"
          elsif summary[:matched_buckets].to_i.zero?
            "insufficient_comparison_data"
          elsif measured < BENEFIT_ADVISORY_MIN_DECISIONS
            "insufficient_data"
          elsif delta.present? && delta <= 0
            "non_positive_benefit"
          else
            "beneficial"
          end

        recommend = status == "non_positive_benefit"
        {
          recommend_tightening: recommend,
          status: status,
          threshold: BENEFIT_ADVISORY_MIN_DECISIONS,
          escalated_measured: measured,
          success_rate_delta: delta,
          message: benefit_advisory_message(status, measured, delta)
        }
      end

      def benefit_advisory_message(status, measured, delta)
        case status
        when "non_positive_benefit"
          "Escalated selections show no measurable benefit (success-rate delta " \
          "#{delta}% across #{measured} escalated decisions with recorded outcomes). " \
          "Consider tightening escalation thresholds (raise the effort-first score bar " \
          "or narrow the frontier gate)."
        when "insufficient_comparison_data"
          "Escalations recorded, but no comparable standard-tier cohort at the same " \
          "complexity level — benefit is not yet measurable."
        when "insufficient_data"
          "Not enough escalated decisions with recorded outcomes to assess benefit " \
          "(need #{BENEFIT_ADVISORY_MIN_DECISIONS}, have #{measured})."
        when "beneficial"
          "Escalated selections show a positive success-rate delta over comparable " \
          "standard-tier selections."
        else
          "No escalations in the selected window."
        end
      end
    end
  end
end
