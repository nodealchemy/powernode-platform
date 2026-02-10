# frozen_string_literal: true

module Ai
  module Intelligence
    class PipelineIntelligenceService
      FAILURE_PATTERNS = {
        timeout: /timeout|timed out|deadline exceeded/i,
        oom: /out of memory|oom|killed|cannot allocate/i,
        dependency: /dependency|not found|missing module|no such file|import error/i,
        permission: /permission denied|access denied|forbidden|unauthorized/i,
        network: /connection refused|network unreachable|dns resolution|ECONNREFUSED/i,
        test_failure: /test failed|assertion|expected.*got|spec failure/i,
        build_error: /compilation error|syntax error|build failed|type error/i,
        config: /configuration error|invalid config|missing env|variable not set/i
      }.freeze

      FIX_SUGGESTIONS = {
        "timeout" => [
          { action: "Increase step timeout configuration", priority: "high" },
          { action: "Check for slow external service dependencies", priority: "medium" },
          { action: "Add timeout-specific retry logic", priority: "medium" }
        ],
        "oom" => [
          { action: "Increase memory allocation for the runner", priority: "high" },
          { action: "Profile memory usage to find leaks", priority: "medium" },
          { action: "Split large operations into smaller batches", priority: "medium" }
        ],
        "dependency" => [
          { action: "Verify all dependencies are declared in package manifest", priority: "high" },
          { action: "Check for version conflicts in dependency tree", priority: "medium" }
        ],
        "permission" => [
          { action: "Verify service account credentials are current", priority: "high" },
          { action: "Check IAM/role permissions for required resources", priority: "high" }
        ],
        "network" => [
          { action: "Verify target service is available and healthy", priority: "high" },
          { action: "Check DNS resolution and firewall rules", priority: "medium" }
        ],
        "test_failure" => [
          { action: "Review test output for specific assertion failures", priority: "high" },
          { action: "Check for flaky tests requiring isolation", priority: "medium" }
        ],
        "build_error" => [
          { action: "Review build output for syntax or type errors", priority: "high" },
          { action: "Ensure build toolchain versions match project requirements", priority: "medium" }
        ],
        "config" => [
          { action: "Verify all required environment variables are set", priority: "high" },
          { action: "Check configuration files for syntax errors", priority: "medium" }
        ]
      }.freeze

      ROOT_CAUSE_DESCRIPTIONS = {
        "timeout" => "Execution exceeded time limits - possible resource contention or slow external services",
        "oom" => "Process ran out of memory - consider increasing resource limits",
        "dependency" => "Missing dependencies or modules - check package installation and import paths",
        "permission" => "Access denied to required resources - verify credentials and permissions",
        "network" => "Network connectivity issues - check service availability and firewall rules",
        "test_failure" => "Test assertions failed - review test output for specific failures",
        "build_error" => "Code compilation or build errors - check syntax and type correctness",
        "config" => "Configuration issues - verify environment variables and config files"
      }.freeze

      PARALLELIZABLE_TYPES = %w[run_tests vulnerability_scan sbom_generate compliance_export].freeze

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Analyze a failed pipeline run - root cause + suggested fixes
      def analyze_failure(pipeline_run_id:)
        run = find_pipeline_run!(pipeline_run_id)
        return run unless run.is_a?(Devops::PipelineRun)
        return error_hash("Pipeline run is not in failure state (status: #{run.status})") unless run.status == "failure"

        failed_steps = run.step_executions.failed.includes(:pipeline_step)
        all_steps = run.step_executions.includes(:pipeline_step).ordered

        analysis = failed_steps.map { |s| analyze_step_failure(s) }
        root_cause = determine_root_cause(analysis)
        recurrence = check_failure_recurrence(run.pipeline, root_cause[:category])

        audit_action("analyze_failure", "Devops::PipelineRun", run.id, context: { root_cause: root_cause[:category] })

        success_response(
          pipeline_run_id: run.id, pipeline_name: run.pipeline.name,
          run_number: run.run_number, trigger_type: run.trigger_type, duration_seconds: run.duration_seconds,
          failed_step_count: failed_steps.size, total_step_count: all_steps.size,
          step_analysis: analysis, root_cause: root_cause,
          suggested_fixes: FIX_SUGGESTIONS.fetch(root_cause[:category], [{ action: "Review full step logs for error details", priority: "high" }]),
          recurrence: recurrence,
          execution_timeline: all_steps.map { |se| { step_name: se.step_name, step_type: se.step_type, status: se.status, started_at: se.started_at&.iso8601, completed_at: se.completed_at&.iso8601, duration_seconds: se.duration_seconds } },
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("analyze_failure", e)
      end

      # Analyze pipeline for optimization opportunities
      def optimize_pipeline(pipeline_id:)
        pipeline = find_pipeline!(pipeline_id)
        return pipeline unless pipeline.is_a?(Devops::Pipeline)

        steps = pipeline.ordered_steps.to_a
        recent_runs = pipeline.runs.recent.limit(50)
        successful_runs = recent_runs.select { |r| r.status == "success" }

        optimizations = find_parallelization_opportunities(steps) +
                        find_caching_opportunities(steps, successful_runs) +
                        find_reordering_opportunities(steps, recent_runs)

        duration_analysis = analyze_step_durations(pipeline, successful_runs)
        bottlenecks = duration_analysis.select { |d| d[:percentage_of_total] >= 40.0 }.map { |d| d.merge(recommendation: "This step takes #{d[:percentage_of_total]}% of total pipeline time - consider optimization") }

        audit_action("optimize_pipeline", "Devops::Pipeline", pipeline.id, context: { optimization_count: optimizations.size })

        success_response(
          pipeline_id: pipeline.id, pipeline_name: pipeline.name, step_count: steps.size,
          recent_run_count: recent_runs.size,
          avg_duration_seconds: successful_runs.any? ? (successful_runs.sum(&:duration_seconds).to_f / successful_runs.size).round(1) : nil,
          optimizations: optimizations, duration_analysis: duration_analysis, bottlenecks: bottlenecks,
          estimated_time_savings_seconds: estimate_time_savings(optimizations, duration_analysis),
          optimized_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("optimize_pipeline", e)
      end

      # Predict rollback probability for a deployment
      def predict_rollback_risk(deployment_id:)
        dep = find_deployment!(deployment_id)
        return dep unless dep.is_a?(Devops::SwarmDeployment)

        history = deployment_history_for(dep)
        total = history.count
        rollbacks = history.where(deployment_type: "rollback").count
        failures = history.where(status: "failed").count

        base_prob = total > 0 ? (rollbacks + failures).to_f / total : 0.5
        risk_factors = assess_deployment_risk_factors(dep, history)
        adjusted = [[base_prob + risk_factors.sum { |f| f[:weight] }, 0.0].max, 1.0].min
        tier = adjusted >= 0.7 ? "critical" : adjusted >= 0.5 ? "high" : adjusted >= 0.3 ? "medium" : adjusted >= 0.1 ? "low" : "minimal"

        recommendation = case tier
                         when "critical" then "High rollback risk. Consider delaying deployment or ensuring a validated rollback plan is ready."
                         when "high" then "Elevated rollback risk#{risk_factors.any? ? " due to: #{risk_factors.map { |f| f[:description] }.join('; ')}" : ''}. Monitor closely post-deployment."
                         when "medium" then "Moderate rollback risk. Standard deployment procedures should suffice with monitoring."
                         else "Low rollback risk. Proceed with standard deployment."
                         end

        success_response(
          deployment_id: dep.id, deployment_type: dep.deployment_type, status: dep.status,
          rollback_probability: adjusted.round(3), risk_tier: tier, risk_factors: risk_factors,
          historical_context: {
            total_deployments: total, rollback_count: rollbacks, failure_count: failures,
            historical_rollback_rate: total > 0 ? (rollbacks.to_f / total).round(3) : nil,
            historical_failure_rate: total > 0 ? (failures.to_f / total).round(3) : nil
          },
          recommendation: recommendation, predicted_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("predict_rollback_risk", e)
      end

      # Analyze failure patterns over time
      def failure_trends(period_days: 30)
        cutoff = period_days.days.ago
        runs = Devops::PipelineRun.where(pipeline: account_pipelines).where("devops_pipeline_runs.created_at >= ?", cutoff)
        total_runs = runs.count
        failed_runs = runs.failed
        failure_rate = total_runs > 0 ? (failed_runs.count.to_f / total_runs * 100).round(2) : 0

        weekly = build_weekly_failure_trends(runs, period_days)
        category_counts = categorize_failures(failed_runs)

        pipeline_failures = failed_runs.joins(:pipeline).group("devops_pipelines.id", "devops_pipelines.name")
                                       .select("devops_pipelines.id", "devops_pipelines.name", "COUNT(*) as failure_count")
                                       .order("failure_count DESC").limit(10)

        step_failures = Devops::StepExecution.joins(:pipeline_step, pipeline_run: :pipeline)
                                             .where(devops_pipelines: { account_id: @account.id })
                                             .where("devops_step_executions.created_at >= ?", cutoff)
                                             .failed.group("devops_pipeline_steps.step_type").count
                                             .sort_by { |_, v| -v }.first(10).to_h

        success_response(
          period_days: period_days, total_runs: total_runs, failed_runs: failed_runs.count,
          failure_rate: failure_rate, weekly_trends: weekly, failure_categories: category_counts,
          most_failing_pipelines: pipeline_failures.map { |pf| { id: pf.id, name: pf.name, failures: pf.failure_count } },
          most_failing_step_types: step_failures, trajectory: failure_trajectory(weekly),
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("failure_trends", e)
      end

      # Overall pipeline health across all account pipelines
      def health_check
        pipelines = account_pipelines.active
        window = 7.days.ago

        pipeline_health = pipelines.map do |p|
          recent = p.runs.where("created_at >= ?", window)
          total = recent.count
          ok = recent.successful.count
          fail_count = recent.failed.count
          last_run = p.runs.recent.first
          rate = total > 0 ? ok.to_f / total : 0
          status = total.zero? ? "inactive" : rate >= 0.95 ? "healthy" : rate >= 0.80 ? "degraded" : rate >= 0.50 ? "unhealthy" : "critical"

          { pipeline_id: p.id, pipeline_name: p.name, pipeline_type: p.pipeline_type, is_active: p.is_active,
            recent_runs: total, successful: ok, failed: fail_count,
            success_rate: total > 0 ? (rate * 100).round(1) : nil,
            avg_duration_seconds: recent.successful.average(:duration_seconds)&.round(1),
            last_run_status: last_run&.status, last_run_at: last_run&.created_at&.iso8601, health_status: status }
        end

        statuses = pipeline_health.map { |p| p[:health_status] }
        overall = if pipeline_health.empty? then "no_pipelines"
                  elsif statuses.any? { |s| s == "critical" } then "critical"
                  elsif statuses.count { |s| s == "unhealthy" } > statuses.size / 3 then "unhealthy"
                  elsif statuses.any? { |s| s.in?(%w[degraded unhealthy]) } then "degraded"
                  else "healthy"
                  end

        success_response(
          total_pipelines: pipelines.count, active_pipelines: pipelines.count, overall_health: overall,
          pipelines: pipeline_health, health_distribution: pipeline_health.group_by { |p| p[:health_status] }.transform_values(&:count),
          checked_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("health_check", e)
      end

      private

      def analyze_step_failure(se)
        combined = "#{se.logs}\n#{se.error_message}"
        cat = detect_failure_category(combined)
        error_lines = combined.split("\n").reject(&:blank?).select { |l| l.match?(/error|fail|exception|fatal/i) }
        error_lines = combined.split("\n").reject(&:blank?).last(10) if error_lines.empty?
        { step_name: se.step_name, step_type: se.step_type, status: se.status, error_message: se.error_message,
          failure_category: cat, error_context: error_lines.first(10),
          duration_seconds: se.duration_seconds, started_at: se.started_at&.iso8601, completed_at: se.completed_at&.iso8601 }
      end

      def detect_failure_category(text)
        FAILURE_PATTERNS.each { |cat, pat| return cat.to_s if pat.match?(text) }
        "unknown"
      end

      def determine_root_cause(analysis)
        return { category: "unknown", confidence: 0, description: "No failed steps found" } if analysis.empty?
        cats = analysis.map { |a| a[:failure_category] }
        primary = cats.tally.max_by { |_, c| c }&.first || "unknown"
        { category: primary, confidence: (cats.count(primary).to_f / cats.size).round(2),
          description: ROOT_CAUSE_DESCRIPTIONS.fetch(primary, "Unable to automatically determine root cause - manual log review recommended"),
          affected_steps: analysis.select { |a| a[:failure_category] == primary }.map { |a| a[:step_name] } }
      end

      def check_failure_recurrence(pipeline, category)
        recent = pipeline.runs.failed.where("created_at >= ?", 30.days.ago).limit(20)
        return { recurring: false, occurrences: 0 } if recent.empty?
        matching = recent.count { |r| r.step_executions.failed.any? { |s| detect_failure_category("#{s.logs}\n#{s.error_message}") == category } }
        { recurring: matching > 2, occurrences: matching, in_last_days: 30,
          pattern: matching > 2 ? "This failure type has occurred #{matching} times in the last 30 days" : nil }
      end

      def find_parallelization_opportunities(steps)
        groups = []
        current = []
        steps.each do |s|
          if PARALLELIZABLE_TYPES.include?(s.step_type) && s.condition.blank?
            current << s
          else
            groups << current.dup if current.size > 1
            current = []
          end
        end
        groups << current if current.size > 1
        groups.map do |g|
          { type: "parallelization", priority: "medium", description: "Steps can run in parallel: #{g.map(&:name).join(', ')}",
            affected_steps: g.map(&:name), potential_savings: "Up to #{g.size - 1}x faster for these steps" }
        end
      end

      def find_caching_opportunities(steps, successful_runs)
        steps.select { |s| s.step_type.in?(%w[checkout custom]) && s.name.match?(/install|setup|dependencies/i) }.filter_map do |step|
          avg = step_avg_duration(step, successful_runs)
          next unless avg && avg > 30
          { type: "caching", priority: avg > 120 ? "high" : "medium",
            description: "Cache dependencies for '#{step.name}' (avg #{avg.round(0)}s)",
            affected_steps: [step.name], potential_savings: "~#{(avg * 0.7).round(0)}s per run with warm cache" }
        end
      end

      def find_reordering_opportunities(steps, recent_runs)
        steps.filter_map do |step|
          execs = Devops::StepExecution.where(pipeline_step: step, pipeline_run: recent_runs)
          total = execs.count
          next if total < 5
          rate = execs.failed.count.to_f / total
          next if rate <= 0.2 || step.position <= 1
          { type: "reordering", priority: "medium",
            description: "Move '#{step.name}' earlier - #{(rate * 100).round(0)}% failure rate wastes prior step execution time",
            affected_steps: [step.name], current_position: step.position, failure_rate: (rate * 100).round(1) }
        end
      end

      def analyze_step_durations(pipeline, successful_runs)
        return [] if successful_runs.empty?
        durations = pipeline.ordered_steps.filter_map do |step|
          avg = step_avg_duration(step, successful_runs)
          next unless avg
          { step_name: step.name, step_type: step.step_type, avg_duration_seconds: avg.round(1), percentage_of_total: nil }
        end
        total = durations.sum { |d| d[:avg_duration_seconds] }
        durations.each { |d| d[:percentage_of_total] = total > 0 ? (d[:avg_duration_seconds] / total * 100).round(1) : 0 }
        durations
      end

      def step_avg_duration(step, successful_runs)
        Devops::StepExecution.where(pipeline_step: step, pipeline_run: successful_runs).successful.average(:duration_seconds)&.to_f
      end

      def estimate_time_savings(opts, durations)
        opts.sum do |opt|
          affected = durations.select { |d| opt[:affected_steps].include?(d[:step_name]) }
          case opt[:type]
          when "parallelization"
            affected.size > 1 ? affected.sort_by { |d| -d[:avg_duration_seconds] }[1..].sum { |d| d[:avg_duration_seconds] } : 0
          when "caching"
            affected.sum { |d| d[:avg_duration_seconds] * 0.7 }
          else 0
          end
        end.round(1)
      end

      def deployment_history_for(dep)
        scope = Devops::SwarmDeployment.where(cluster_id: dep.cluster_id)
        scope = scope.where(service_id: dep.service_id) if dep.service_id.present?
        scope = scope.where(stack_id: dep.stack_id) if dep.stack_id.present?
        scope.where("created_at >= ?", 90.days.ago).recent
      end

      def assess_deployment_risk_factors(dep, history)
        factors = []
        rf = history.where(status: "failed").where("created_at >= ?", 7.days.ago).count
        factors << { factor: "recent_failures", weight: 0.15, description: "#{rf} failed deployments in last 7 days" } if rf > 0
        rb = history.where(deployment_type: "rollback").where("created_at >= ?", 14.days.ago).count
        factors << { factor: "recent_rollbacks", weight: 0.10, description: "#{rb} rollbacks in last 14 days" } if rb > 0
        dt = history.where("created_at >= ?", Time.current.beginning_of_day).count
        factors << { factor: "high_deploy_frequency", weight: 0.10, description: "#{dt} deployments today" } if dt > 3
        h = Time.current.hour
        factors << { factor: "off_hours_deployment", weight: 0.05, description: "Deployment outside business hours" } if h < 6 || h > 20
        factors
      end

      def build_weekly_failure_trends(runs, period_days)
        weeks = (period_days / 7.0).ceil
        cutoff = period_days.days.ago.beginning_of_week
        (0...weeks).map do |i|
          ws = cutoff + i.weeks
          period_runs = runs.where(devops_pipeline_runs: { created_at: ws..(ws + 1.week) })
          total = period_runs.count
          failed = period_runs.failed.count
          { week_start: ws.to_date.iso8601, total_runs: total, failed_runs: failed, failure_rate: total > 0 ? (failed.to_f / total * 100).round(1) : 0 }
        end
      end

      def categorize_failures(failed_runs)
        counts = Hash.new(0)
        failed_runs.find_each { |r| r.step_executions.failed.each { |s| counts[detect_failure_category("#{s.logs}\n#{s.error_message}")] += 1 } }
        counts.sort_by { |_, v| -v }.to_h
      end

      def failure_trajectory(weekly)
        return "insufficient_data" if weekly.size < 2
        recent_avg = weekly.last(2).map { |w| w[:failure_rate] }.sum / 2
        older_avg = weekly.first([weekly.size - 2, 1].max).map { |w| w[:failure_rate] }.sum / [weekly.size - 2, 1].max
        recent_avg < older_avg - 5 ? "improving" : recent_avg > older_avg + 5 ? "worsening" : "stable"
      end

      def find_pipeline_run!(id)
        Devops::PipelineRun.joins(:pipeline).where(devops_pipelines: { account_id: @account.id }).find_by(id: id) || error_hash("Pipeline run not found: #{id}")
      end

      def find_pipeline!(id)
        Devops::Pipeline.where(account: @account).find_by(id: id) || error_hash("Pipeline not found: #{id}")
      end

      def find_deployment!(id)
        Devops::SwarmDeployment.joins(:cluster).find_by(id: id) || error_hash("Deployment not found: #{id}")
      end

      def account_pipelines = Devops::Pipeline.where(account: @account)

      def audit_action(action, resource_type, resource_id, context: {})
        Ai::ComplianceAuditEntry.log!(account: @account, action_type: "ai_intelligence_#{action}", resource_type: resource_type, resource_id: resource_id, outcome: "success", description: "AI Intelligence: #{action.humanize}", context: context)
      rescue StandardError => e
        @logger.warn("Failed to log audit entry for #{action}: #{e.message}")
      end

      def success_response(**data) = { success: true }.merge(data)

      def error_response(method_name, exception)
        @logger.error("[Ai::Intelligence::PipelineIntelligenceService##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end

      def error_hash(message) = { success: false, error: message }
    end
  end
end
