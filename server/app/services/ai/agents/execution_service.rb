# frozen_string_literal: true

module Ai
  module Agents
    # Service for managing agent executions
    #
    # Provides execution management including:
    # - Execution cancellation
    # - Execution retry
    # - Execution logs
    # - Execution updates
    #
    # Usage:
    #   service = Ai::Agents::ExecutionService.new(execution: execution, user: current_user)
    #   result = service.cancel(reason: "User cancelled")
    #
    class ExecutionService
      attr_reader :execution, :user

      Result = Struct.new(:success?, :data, :error, keyword_init: true)

      def initialize(execution:, user:)
        @execution = execution
        @user = user
      end

      # Cancel the execution
      # @param reason [String] Cancellation reason
      # @return [Result] Cancel result
      def cancel(reason: "Cancelled by user")
        execution.cancel_execution!(reason)

        Result.new(success?: true, data: { execution: execution })
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to cancel execution: #{e.message}")
      end

      # Retry the execution
      # @return [Result] Retry result with new execution
      def retry
        unless execution.finished?
          return Result.new(success?: false, error: "Cannot retry execution that is not finished")
        end

        new_execution = execution.agent.execute(
          execution.input_parameters,
          user: user,
          provider: execution.provider
        )

        Result.new(
          success?: true,
          data: {
            execution: new_execution,
            original_execution_id: execution.execution_id
          }
        )
      rescue StandardError => e
        Result.new(success?: false, error: "Failed to retry execution: #{e.message}")
      end

      # Update execution attributes
      # @param attributes [Hash] Attributes to update
      # @return [Result] Update result
      def update(attributes)
        if execution.update(attributes)
          Result.new(success?: true, data: { execution: execution })
        else
          Result.new(success?: false, error: execution.errors.full_messages.join(", "))
        end
      rescue StandardError => e
        Result.new(success?: false, error: "Update failed: #{e.message}")
      end

      # Build execution logs
      # @return [Array<Hash>] Execution logs
      def logs
        logs = []

        if execution.started_at
          logs << {
            timestamp: execution.started_at.iso8601,
            level: "info",
            message: "Execution started",
            data: { status: "running" }
          }
        end

        if execution.completed_at
          logs << {
            timestamp: execution.completed_at.iso8601,
            level: execution.successful? ? "info" : "error",
            message: execution.successful? ? "Execution completed" : "Execution failed",
            data: {
              status: execution.status,
              duration_ms: execution.duration_ms,
              cost_usd: execution.cost_usd
            }
          }
        end

        if execution.error_details.present?
          logs << {
            timestamp: execution.completed_at&.iso8601 || Time.current.iso8601,
            level: "error",
            message: "Execution error",
            data: execution.error_details
          }
        end

        logs.sort_by { |log| log[:timestamp] }
      end
    end
  end
end
