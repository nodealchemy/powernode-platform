# frozen_string_literal: true

module Ai
  module Agents
    # Service for managing agent lifecycle operations
    #
    # Provides agent management including:
    # - Agent execution
    # - Agent cloning
    # - Agent testing and validation
    # - Agent statistics and analytics
    #
    # Usage:
    #   service = Ai::Agents::ManagementService.new(agent: agent, user: current_user)
    #   result = service.execute(input_parameters: {}, provider_id: nil)
    #
    class ManagementService
      attr_reader :agent, :user, :account

      Result = Struct.new(:success?, :data, :error, keyword_init: true)

      def initialize(agent:, user:)
        @agent = agent
        @user = user
        @account = user.account
      end

      # Execute the agent
      # @param input_parameters [Hash] Input parameters for execution
      # @param provider_id [String] Optional provider ID override
      # @return [Result] Execution result with execution object
      def execute(input_parameters: {}, provider_id: nil)
        unless agent.mcp_available?
          return Result.new(success?: false, error: "Agent cannot be executed in current state")
        end

        provider = resolve_provider(provider_id)
        return Result.new(success?: false, error: "AI provider not found") if provider_id.present? && provider.nil?

        # Check budget gate
        active_budget = Ai::AgentBudget.where(agent_id: agent.id, account_id: account.id).active.first
        if active_budget&.over_budget?
          return Result.new(success?: false, error: "Agent budget exhausted. Remaining: $#{(active_budget.remaining_cents / 100.0).round(2)}")
        end

        execution = agent.execute(
          input_parameters,
          user: user,
          provider: provider
        )

        Result.new(success?: true, data: { execution: execution, agent: agent.reload })
      rescue ArgumentError => e
        Result.new(success?: false, error: e.message)
      rescue ActiveRecord::RecordInvalid => e
        Result.new(success?: false, error: e.record.errors.full_messages.join(", "))
      end

      # Clone the agent
      # @return [Result] Clone result with cloned agent
      def clone
        cloned_agent = agent.clone_for_account(account, user)

        Result.new(success?: true, data: { agent: cloned_agent, original_agent_id: agent.id })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to clone agent: #{e.message}")
      end

      # Test the agent with input
      # @param test_input [Hash] Test input parameters
      # @return [Result] Test result
      def test(test_input: {})
        result = agent.test_execution(test_input, user)

        Result.new(success?: true, data: { test_result: result })
      rescue StandardError => e
        Result.new(success?: false, error: "Test execution failed: #{e.message}")
      end

      # Validate agent configuration
      # @return [Result] Validation result
      def validate
        validation_result = agent.validate_configuration

        Result.new(
          success?: true,
          data: {
            valid: validation_result[:valid],
            errors: validation_result[:errors],
            warnings: validation_result[:warnings]
          }
        )
      end

      # Pause the agent
      # @return [Result] Pause result
      def pause
        unless agent.active?
          return Result.new(success?: false, error: "Agent must be active to pause")
        end

        agent.update!(status: "paused")
        Result.new(success?: true, data: { agent: agent })
      end

      # Resume the agent
      # @return [Result] Resume result
      def resume
        unless agent.paused?
          return Result.new(success?: false, error: "Agent must be paused to resume")
        end

        agent.update!(status: "active")
        Result.new(success?: true, data: { agent: agent })
      end

      # Archive the agent
      # @return [Result] Archive result
      def archive
        agent.update!(status: "archived")
        Result.new(success?: true, data: { agent: agent })
      end

      # Get agent statistics
      # @return [Hash] Agent statistics
      def stats
        executions = agent.executions

        {
          total_executions: executions.count,
          successful_executions: executions.where(status: "completed").count,
          failed_executions: executions.where(status: "failed").count,
          running_executions: executions.where(status: "running").count,
          average_duration: executions.where.not(completed_at: nil)
                                      .average("EXTRACT(epoch FROM (completed_at - started_at))"),
          total_cost: executions.sum(:cost_usd),
          last_executed_at: executions.maximum(:created_at),
          success_rate: calculate_success_rate(executions)
        }
      end

      # Get agent analytics over a date range
      # @param date_range [Integer] Number of days to look back
      # @return [Hash] Analytics data
      def analytics(date_range: 30)
        executions = agent.executions.where("created_at >= ?", date_range.days.ago)

        {
          executions_over_time: executions.group_by_day(:created_at).count,
          status_distribution: executions.group(:status).count,
          average_cost_per_day: executions.group_by_day(:created_at).average(:cost_usd),
          performance_metrics: calculate_performance_metrics(executions)
        }
      end

      # Get aggregate statistics for all account agents
      # @return [Hash] Account-wide agent statistics
      def account_statistics
        agents = account.ai_agents

        {
          total_agents: agents.count,
          active_agents: agents.where(status: "active").count,
          paused_agents: agents.where(status: "paused").count,
          total_executions: ::Ai::AgentExecution.joins(:agent)
                                                .where(ai_agents: { account_id: account.id })
                                                .count,
          agents_by_type: agents.group(:agent_type).count,
          recent_activity: agents.joins(:executions)
                                 .where(ai_agent_executions: { created_at: 7.days.ago.. })
                                 .group("ai_agents.id")
                                 .count
        }
      end

      private

      def resolve_provider(provider_id)
        return nil unless provider_id.present?
        account.ai_providers.find_by(id: provider_id)
      end

      def calculate_success_rate(executions)
        total = executions.count
        return 0 if total.zero?

        successful = executions.where(status: "completed").count
        ((successful.to_f / total) * 100).round(2)
      end

      def calculate_performance_metrics(executions)
        durations = executions.where.not(completed_at: nil)
                              .pluck(Arel.sql("EXTRACT(epoch FROM (completed_at - started_at))"))
                              .compact

        {
          average_duration: durations.empty? ? 0 : (durations.sum / durations.size).round(2),
          min_duration: durations.min&.round(2) || 0,
          max_duration: durations.max&.round(2) || 0,
          median_duration: calculate_median(durations)
        }
      end

      def calculate_median(values)
        return 0 if values.empty?

        sorted = values.sort
        mid = sorted.length / 2

        if sorted.length.odd?
          sorted[mid].round(2)
        else
          ((sorted[mid - 1] + sorted[mid]) / 2.0).round(2)
        end
      end
    end
  end
end
