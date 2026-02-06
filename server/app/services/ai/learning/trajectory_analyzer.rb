# frozen_string_literal: true

module Ai
  module Learning
    class TrajectoryAnalyzer
      MIN_SAMPLE_SIZE = 10

      def initialize(account:)
        @account = account
      end

      def analyze
        return [] unless Shared::FeatureFlagService.enabled?(:trajectory_analysis)

        analyses = []
        analyses.concat(analyze_provider_performance)
        analyses.concat(analyze_team_compositions)
        analyses.concat(analyze_cost_efficiency)
        analyses.concat(analyze_failure_modes)
        analyses
      end

      private

      def analyze_provider_performance
        recommendations = []

        Ai::Agent.where(account: @account).find_each do |agent|
          executions = Ai::AgentExecution.where(agent: agent)
                                         .where("created_at >= ?", 30.days.ago)

          next if executions.count < MIN_SAMPLE_SIZE

          provider_stats = executions.group(:ai_provider_id).select(
            "ai_provider_id",
            "COUNT(*) as total",
            "COUNT(CASE WHEN status = 'completed' THEN 1 END) as successes",
            "AVG(duration_ms) as avg_duration",
            "AVG(cost_usd) as avg_cost"
          )

          current_provider_id = agent.ai_provider_id
          current_stats = provider_stats.find { |s| s.ai_provider_id == current_provider_id }
          next unless current_stats

          best = provider_stats.max_by { |s| s.total > 0 ? s.successes.to_f / s.total : 0 }
          next unless best && best.ai_provider_id != current_provider_id

          current_rate = current_stats.total > 0 ? (current_stats.successes.to_f / current_stats.total * 100).round(1) : 0
          best_rate = best.total > 0 ? (best.successes.to_f / best.total * 100).round(1) : 0

          next unless best_rate - current_rate >= 10

          best_provider = Ai::Provider.find_by(id: best.ai_provider_id)
          next unless best_provider

          confidence = calculate_confidence(best.total, best_rate, current_stats.total, current_rate)

          recommendations << {
            recommendation_type: "provider_switch",
            target_type: "Ai::Agent",
            target_id: agent.id,
            current_config: { provider_id: current_provider_id, success_rate: current_rate },
            recommended_config: { provider_id: best.ai_provider_id, success_rate: best_rate },
            evidence: {
              agent_name: agent.name,
              current_provider: Ai::Provider.find_by(id: current_provider_id)&.name,
              recommended_provider: best_provider.name,
              sample_size: best.total,
              improvement: "#{(best_rate - current_rate).round(1)}% higher success rate"
            },
            confidence_score: confidence
          }
        end

        recommendations
      end

      def analyze_team_compositions
        recommendations = []

        Ai::AgentTeam.where(account: @account).find_each do |team|
          # Analyze team execution history from trajectories
          trajectories = Ai::Trajectory.where(account: @account)
                                       .where("metadata->>'team_id' = ?", team.id.to_s)
                                       .where("created_at >= ?", 30.days.ago)

          next if trajectories.count < MIN_SAMPLE_SIZE

          success_count = trajectories.where(status: "completed").count
          success_rate = (success_count.to_f / trajectories.count * 100).round(1)

          next unless success_rate < 70

          recommendations << {
            recommendation_type: "team_composition",
            target_type: "Ai::AgentTeam",
            target_id: team.id,
            current_config: { member_count: team.team_members.count, success_rate: success_rate },
            recommended_config: {},
            evidence: {
              team_name: team.name,
              sample_size: trajectories.count,
              success_rate: success_rate,
              suggestion: "Team success rate below 70%. Review member roles and capabilities."
            },
            confidence_score: 0.5
          }
        end

        recommendations
      rescue => e
        Rails.logger.error "[TrajectoryAnalyzer] Team analysis failed: #{e.message}"
        []
      end

      def analyze_cost_efficiency
        recommendations = []

        provider_costs = Ai::AgentExecution.where(account: @account)
                                           .where("created_at >= ?", 30.days.ago)
                                           .where(status: "completed")
                                           .group(:ai_provider_id)
                                           .select(
                                             "ai_provider_id",
                                             "AVG(cost_usd) as avg_cost",
                                             "COUNT(*) as total",
                                             "AVG(CASE WHEN status = 'completed' THEN 1.0 ELSE 0.0 END) as quality"
                                           )

        return recommendations if provider_costs.count < 2

        sorted = provider_costs.sort_by { |p| p.avg_cost || Float::INFINITY }
        cheapest = sorted.first
        most_expensive = sorted.last

        return recommendations unless cheapest && most_expensive
        return recommendations unless cheapest.avg_cost && most_expensive.avg_cost
        return recommendations if cheapest.ai_provider_id == most_expensive.ai_provider_id

        savings = ((most_expensive.avg_cost - cheapest.avg_cost) / most_expensive.avg_cost * 100).round(1)

        if savings >= 20
          recommendations << {
            recommendation_type: "cost_optimization",
            target_type: "Account",
            target_id: @account.id,
            current_config: { primary_provider: most_expensive.ai_provider_id },
            recommended_config: { primary_provider: cheapest.ai_provider_id },
            evidence: {
              savings_percent: savings,
              cheapest_provider: Ai::Provider.find_by(id: cheapest.ai_provider_id)&.name,
              expensive_provider: Ai::Provider.find_by(id: most_expensive.ai_provider_id)&.name,
              suggestion: "#{savings}% cost reduction possible by switching default provider"
            },
            confidence_score: 0.6
          }
        end

        recommendations
      rescue => e
        Rails.logger.error "[TrajectoryAnalyzer] Cost analysis failed: #{e.message}"
        []
      end

      def analyze_failure_modes
        recommendations = []

        # Find workflows with high failure rates at specific nodes
        Ai::Workflow.where(account: @account).find_each do |workflow|
          node_failures = Ai::WorkflowNodeExecution.joins(:workflow_run)
                                                    .where(ai_workflow_runs: { ai_workflow_id: workflow.id })
                                                    .where("ai_workflow_node_executions.created_at >= ?", 30.days.ago)
                                                    .group(:ai_workflow_node_id)
                                                    .select(
                                                      "ai_workflow_node_id",
                                                      "COUNT(*) as total",
                                                      "COUNT(CASE WHEN ai_workflow_node_executions.status = 'failed' THEN 1 END) as failures"
                                                    )

          node_failures.each do |nf|
            next if nf.total < MIN_SAMPLE_SIZE

            failure_rate = (nf.failures.to_f / nf.total * 100).round(1)
            next unless failure_rate >= 30

            node = Ai::WorkflowNode.find_by(id: nf.ai_workflow_node_id)
            next unless node

            recommendations << {
              recommendation_type: "timeout_adjustment",
              target_type: "Ai::WorkflowNode",
              target_id: node.id,
              current_config: { node_name: node.name, failure_rate: failure_rate },
              recommended_config: {},
              evidence: {
                workflow_name: workflow.name,
                node_name: node.name,
                failure_rate: failure_rate,
                sample_size: nf.total,
                suggestion: "Node '#{node.name}' fails #{failure_rate}% of the time. Check timeout or configuration."
              },
              confidence_score: [failure_rate / 100.0, 0.9].min
            }
          end
        end

        recommendations
      rescue => e
        Rails.logger.error "[TrajectoryAnalyzer] Failure mode analysis failed: #{e.message}"
        []
      end

      def calculate_confidence(sample_size, rate, baseline_size, baseline_rate)
        # Simple confidence based on sample size and improvement delta
        size_factor = [sample_size.to_f / 50, 1.0].min
        delta_factor = [(rate - baseline_rate) / 100.0, 0.5].min
        [size_factor * 0.6 + delta_factor * 0.8, 0.95].min.round(4)
      end
    end
  end
end
