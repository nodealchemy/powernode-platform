# frozen_string_literal: true

module Ai
  module Teams
    class AnalyticsService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      def get_team_analytics(team_id, period_days: 30)
        team = find_team(team_id)
        start_date = period_days.days.ago

        executions = team.team_executions.where("created_at >= ?", start_date)
        tasks = Ai::TeamTask.joins(:team_execution).where(ai_team_executions: { agent_team_id: team.id }).where("ai_team_tasks.created_at >= ?", start_date)
        messages = Ai::TeamMessage.joins(:team_execution).where(ai_team_executions: { agent_team_id: team.id }).where("ai_team_messages.created_at >= ?", start_date)
        reviews = Ai::TaskReview.joins(team_task: :team_execution).where(ai_team_executions: { agent_team_id: team.id }).where("ai_task_reviews.created_at >= ?", start_date)
        learnings = team.compound_learnings.where(status: "active")

        completed_execs = executions.where(status: "completed")
        failed_execs = executions.where(status: "failed")
        cancelled_execs = executions.where(status: "cancelled")
        active_execs = executions.where(status: %w[running paused pending])
        total_exec_count = executions.count

        {
          period_days: period_days,
          generated_at: Time.current.iso8601,

          overview: {
            total_executions: total_exec_count,
            completed_executions: completed_execs.count,
            failed_executions: failed_execs.count,
            cancelled_executions: cancelled_execs.count,
            active_executions: active_execs.count,
            success_rate: calculate_success_rate(executions),
            total_tasks: tasks.count,
            completed_tasks: tasks.where(status: "completed").count,
            failed_tasks: tasks.where(status: "failed").count,
            total_messages: messages.count,
            total_tokens_used: executions.sum(:total_tokens_used),
            total_cost_usd: executions.sum(:total_cost_usd).to_f.round(4),
            executions_by_day: executions.group_by_day(:created_at).count,
            cost_by_day: completed_execs.group_by_day(:created_at).sum(:total_cost_usd)
          },

          performance: build_performance_analytics(executions, completed_execs, tasks, messages, total_exec_count),
          cost: build_cost_analytics(executions, completed_execs, tasks, messages, total_exec_count),
          agents: build_agent_analytics(team, tasks, messages),
          communication: build_communication_analytics(messages, team),
          quality: build_quality_analytics(reviews, learnings)
        }
      end

      def get_execution_details(execution_id)
        execution = find_execution(execution_id)

        {
          execution: execution,
          tasks: execution.tasks.includes(:assigned_role, :assigned_agent).order(:created_at),
          messages: execution.messages.includes(:from_role, :to_role, :channel).ordered,
          shared_memory: execution.shared_memory,
          performance: {
            duration_ms: execution.duration_ms,
            tasks_total: execution.tasks_total,
            tasks_completed: execution.tasks_completed,
            tasks_failed: execution.tasks_failed,
            messages_exchanged: execution.messages_exchanged,
            total_tokens: execution.total_tokens_used,
            total_cost: execution.total_cost_usd
          }
        }
      end

      private

      def find_team(team_id)
        account.ai_agent_teams.find(team_id)
      end

      def find_execution(execution_id)
        account.ai_team_executions.find(execution_id)
      end

      def build_performance_analytics(executions, completed_execs, tasks, messages, total_exec_count)
        durations = completed_execs.where.not(duration_ms: nil).pluck(:duration_ms).sort

        {
          avg_duration_ms: completed_execs.average(:duration_ms)&.round(2),
          median_duration_ms: calculate_percentile(durations, 50),
          p95_duration_ms: calculate_percentile(durations, 95),
          min_duration_ms: durations.first,
          max_duration_ms: durations.last,
          avg_tasks_per_execution: total_exec_count.positive? ? (tasks.count.to_f / total_exec_count).round(2) : 0,
          avg_messages_per_execution: total_exec_count.positive? ? (messages.count.to_f / total_exec_count).round(2) : 0,
          throughput_per_day: total_exec_count.positive? ? (completed_execs.count.to_f / [(executions.maximum(:created_at).to_date - executions.minimum(:created_at).to_date).to_i, 1].max).round(2) : 0,
          status_breakdown: executions.group(:status).count,
          termination_reasons: executions.where.not(termination_reason: [nil, ""]).group(:termination_reason).count,
          duration_by_day: completed_execs.group_by_day(:created_at).average(:duration_ms),
          slowest_executions: completed_execs.where.not(duration_ms: nil).order(duration_ms: :desc).limit(5).map { |e|
            { id: e.id, execution_id: e.execution_id, objective: e.objective&.truncate(100), duration_ms: e.duration_ms, tasks_total: e.tasks_total, created_at: e.created_at.iso8601 }
          }
        }
      end

      def build_cost_analytics(executions, completed_execs, tasks, messages, total_exec_count)
        total_cost = executions.sum(:total_cost_usd).to_f
        total_tokens = executions.sum(:total_tokens_used)
        tasks_count = tasks.count
        messages_count = messages.count

        {
          total_cost_usd: total_cost.round(4),
          total_tokens: total_tokens,
          avg_cost_per_execution: total_exec_count.positive? ? (total_cost / total_exec_count).round(4) : 0,
          avg_tokens_per_execution: total_exec_count.positive? ? (total_tokens.to_f / total_exec_count).round(0) : 0,
          cost_by_day: executions.group_by_day(:created_at).sum(:total_cost_usd),
          tokens_by_day: executions.group_by_day(:created_at).sum(:total_tokens_used),
          cost_by_status: executions.group(:status).sum(:total_cost_usd),
          tokens_by_status: executions.group(:status).sum(:total_tokens_used),
          top_cost_executions: executions.where("total_cost_usd > 0").order(total_cost_usd: :desc).limit(5).map { |e|
            { id: e.id, execution_id: e.execution_id, objective: e.objective&.truncate(100), cost_usd: e.total_cost_usd.to_f.round(4), tokens: e.total_tokens_used, created_at: e.created_at.iso8601 }
          },
          cost_per_task: tasks_count.positive? ? (total_cost / tasks_count).round(4) : 0,
          cost_per_message: messages_count.positive? ? (total_cost / messages_count).round(6) : 0
        }
      end

      def build_agent_analytics(team, tasks, messages)
        roles = team.ai_team_roles.includes(:ai_agent)
        role_stats = roles.map do |role|
          role_tasks = tasks.where(assigned_role_id: role.id)
          role_msgs_sent = messages.where(from_role_id: role.id)
          role_msgs_received = messages.where(to_role_id: role.id)

          tools_hash = {}
          role_tasks.where.not(tools_used: nil).pluck(:tools_used).each do |tools|
            Array(tools).each { |t| tools_hash[t] = (tools_hash[t] || 0) + 1 }
          end

          completed_count = role_tasks.where(status: "completed").count
          total_finished = role_tasks.where(status: %w[completed failed]).count

          {
            role_id: role.id,
            role_name: role.role_name,
            role_type: role.role_type,
            agent_name: role.ai_agent&.name,
            tasks_total: role_tasks.count,
            tasks_completed: completed_count,
            tasks_failed: role_tasks.where(status: "failed").count,
            success_rate: total_finished.positive? ? ((completed_count.to_f / total_finished) * 100).round(2) : 0,
            avg_duration_ms: role_tasks.where.not(duration_ms: nil).average(:duration_ms)&.round(2),
            total_tokens: role_tasks.sum(:tokens_used),
            total_cost_usd: role_tasks.sum(:cost_usd).to_f.round(4),
            messages_sent: role_msgs_sent.count,
            messages_received: role_msgs_received.count,
            tools_used: tools_hash,
            avg_retries: role_tasks.average(:retry_count)&.round(2) || 0
          }
        end

        all_tools = {}
        role_stats.each { |rs| rs[:tools_used].each { |t, c| all_tools[t] = (all_tools[t] || 0) + c } }

        {
          role_stats: role_stats,
          task_type_distribution: tasks.group(:task_type).count,
          workload_by_role: role_stats.each_with_object({}) { |rs, h| h[rs[:role_name]] = rs[:tasks_total] },
          unassigned_tasks: tasks.where(assigned_role_id: nil).count,
          top_tools: all_tools.sort_by { |_, c| -c }.first(10).to_h
        }
      end

      def build_communication_analytics(messages, team)
        total = messages.count
        escalations = messages.where(message_type: "escalation")
        questions = messages.where(message_type: "question")
        answers = messages.where(message_type: "answer")
        requiring_response = messages.where(requires_response: true)
        responded = requiring_response.where.not(responded_at: nil)
        pending = requiring_response.where(responded_at: nil)

        avg_response_seconds = if responded.exists?
                                 responded
                                   .where.not(responded_at: nil)
                                   .pick(Arel.sql("AVG(EXTRACT(EPOCH FROM (ai_team_messages.responded_at - ai_team_messages.created_at)))"))
                                   &.round(2)
                               end

        # Role interaction matrix
        interactions = messages
          .where.not(from_role_id: nil)
          .where.not(to_role_id: nil)
          .group(:from_role_id, :to_role_id)
          .count

        role_names = team.ai_team_roles.pluck(:id, :role_name).to_h
        role_interactions = interactions.map do |(from_id, to_id), count|
          { from: role_names[from_id] || from_id, to: role_names[to_id] || to_id, count: count }
        end

        {
          total_messages: total,
          message_type_distribution: messages.group(:message_type).count,
          priority_distribution: messages.group(:priority).count,
          escalation_count: escalations.count,
          escalation_rate: total.positive? ? ((escalations.count.to_f / total) * 100).round(2) : 0,
          questions_asked: questions.count,
          questions_answered: answers.count,
          pending_responses: pending.count,
          response_rate: requiring_response.count.positive? ? ((responded.count.to_f / requiring_response.count) * 100).round(2) : 0,
          avg_response_time_seconds: avg_response_seconds || 0,
          messages_by_day: messages.group_by_day(:created_at).count,
          role_interactions: role_interactions,
          broadcasts_count: messages.where(message_type: "broadcast").count,
          high_priority_count: messages.where(priority: %w[high critical urgent]).count
        }
      end

      def build_quality_analytics(reviews, learnings)
        total_reviews = reviews.count
        approved = reviews.where(status: "approved").count
        rejected = reviews.where(status: "rejected").count
        revision_requested = reviews.where(status: "revision_requested").count
        pending = reviews.where(status: %w[pending in_progress]).count

        # Quality score distribution in buckets
        score_dist = {}
        if reviews.where.not(quality_score: nil).exists?
          reviews.where.not(quality_score: nil).pluck(:quality_score).each do |score|
            bucket = case score
                     when 0..20 then "0-20"
                     when 21..40 then "21-40"
                     when 41..60 then "41-60"
                     when 61..80 then "61-80"
                     else "81-100"
                     end
            score_dist[bucket] = (score_dist[bucket] || 0) + 1
          end
        end

        # Findings aggregation
        findings_by_severity = {}
        findings_by_category = {}
        reviews.where.not(findings: nil).pluck(:findings).each do |findings_arr|
          Array(findings_arr).each do |f|
            sev = f["severity"] || "unknown"
            cat = f["category"] || "unknown"
            findings_by_severity[sev] = (findings_by_severity[sev] || 0) + 1
            findings_by_category[cat] = (findings_by_category[cat] || 0) + 1
          end
        end

        # Learning metrics
        learning_metrics = if learnings.exists?
                             injected = learnings.where("injection_count > 0")
                             {
                               total_learnings: learnings.count,
                               by_category: learnings.group(:category).count,
                               by_extraction_method: learnings.group(:extraction_method).count,
                               avg_importance: learnings.average(:importance_score)&.round(2) || 0,
                               avg_confidence: learnings.average(:confidence_score)&.round(2) || 0,
                               avg_effectiveness: learnings.average(:effectiveness_score)&.round(2) || 0,
                               total_injections: learnings.sum(:injection_count),
                               positive_outcomes: learnings.sum(:positive_outcome_count),
                               negative_outcomes: learnings.sum(:negative_outcome_count),
                               injection_success_rate: injected.count.positive? ? ((injected.where("positive_outcome_count > negative_outcome_count").count.to_f / injected.count) * 100).round(2) : 0,
                               high_importance_count: learnings.where("importance_score >= ?", 0.8).count
                             }
                           else
                             {
                               total_learnings: 0, by_category: {}, by_extraction_method: {},
                               avg_importance: 0, avg_confidence: 0, avg_effectiveness: 0,
                               total_injections: 0, positive_outcomes: 0, negative_outcomes: 0,
                               injection_success_rate: 0, high_importance_count: 0
                             }
                           end

        {
          total_reviews: total_reviews,
          approved_count: approved,
          rejected_count: rejected,
          revision_requested_count: revision_requested,
          pending_count: pending,
          approval_rate: total_reviews.positive? ? ((approved.to_f / total_reviews) * 100).round(2) : 0,
          avg_quality_score: reviews.average(:quality_score)&.round(2) || 0,
          quality_score_distribution: score_dist,
          avg_review_duration_ms: reviews.average(:review_duration_ms)&.round(2) || 0,
          avg_revision_count: reviews.average(:revision_count)&.round(2) || 0,
          review_mode_breakdown: reviews.group(:review_mode).count,
          findings_by_severity: findings_by_severity,
          findings_by_category: findings_by_category,
          learning: learning_metrics
        }
      end

      def calculate_percentile(sorted_values, percentile)
        return nil if sorted_values.empty?

        k = (percentile / 100.0 * (sorted_values.length - 1)).round
        sorted_values[k]
      end

      def calculate_success_rate(executions)
        return 0.0 if executions.count.zero?

        completed = executions.completed.count
        total = executions.where(status: %w[completed failed]).count
        return 0.0 if total.zero?

        ((completed.to_f / total) * 100).round(2)
      end
    end
  end
end
