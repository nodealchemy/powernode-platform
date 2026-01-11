# frozen_string_literal: true

module Devops
  class ExecutionService
    class ExecutionServiceError < StandardError; end
    class InvalidInstanceError < ExecutionServiceError; end
    class ExecutorNotFoundError < ExecutionServiceError; end

    EXECUTOR_MAPPING = {
      "github_action" => "Devops::GithubActionExecutor",
      "webhook" => "Devops::WebhookExecutor",
      "mcp_server" => "Devops::McpServerExecutor",
      "rest_api" => "Devops::RestApiExecutor"
    }.freeze

    class << self
      # Execute an integration instance
      def execute(instance:, input: {}, triggered_by: nil, context: {})
        validate_instance!(instance)

        execution = create_execution_record(instance, input, triggered_by)

        begin
          executor = build_executor(instance, execution: execution, context: context)
          result = executor.execute(input)

          {
            success: true,
            execution_id: execution.id,
            result: result,
            execution_time_ms: execution.reload.execution_time_ms
          }
        rescue Devops::BaseExecutor::ExecutionError => e
          {
            success: false,
            execution_id: execution.id,
            error: e.message,
            error_class: e.class.name
          }
        end
      end

      # Execute asynchronously (enqueue job)
      def execute_async(instance:, input: {}, triggered_by: nil, context: {})
        validate_instance!(instance)

        execution = create_execution_record(instance, input, triggered_by, status: "queued")

        # Enqueue the job via worker service
        begin
          WorkerJobService.enqueue_job(
            "Devops::IntegrationExecutionJob",
            args: [{
              execution_id: execution.id,
              input: input,
              context: context
            }],
            queue: "integrations"
          )
          job_queued = true
        rescue WorkerJobService::WorkerServiceError => e
          Rails.logger.warn "Worker service unavailable for integration execution: #{e.message}"
          job_queued = false
          execution.update!(status: "failed", error_message: "Worker service unavailable")
        end

        {
          success: true,
          execution_id: execution.id,
          status: job_queued ? "queued" : "failed",
          message: job_queued ? "Execution queued successfully" : "Worker service unavailable"
        }
      end

      # Test connection for an instance
      def test_connection(instance:)
        validate_instance!(instance)

        executor = build_executor(instance)
        result = executor.test_connection

        {
          success: result[:success],
          message: result[:message] || result[:error],
          tested_at: Time.current
        }
      end

      # Get health status for an instance
      def health_check(instance:)
        validate_instance!(instance)

        executor = build_executor(instance)
        executor.health_check
      end

      # Build executor for an instance
      def build_executor(instance, execution: nil, context: {})
        integration_type = instance.template.integration_type
        executor_class_name = EXECUTOR_MAPPING[integration_type]

        raise ExecutorNotFoundError, "No executor for type: #{integration_type}" unless executor_class_name

        executor_class = executor_class_name.constantize
        executor_class.new(instance: instance, execution: execution, context: context)
      end

      # Retry a failed execution
      def retry_execution(execution:, context: {})
        unless execution.can_retry?
          return {
            success: false,
            error: "Execution cannot be retried (max attempts reached or not failed)"
          }
        end

        instance = execution.instance

        # Create new execution as retry
        new_execution = create_execution_record(
          instance,
          execution.input_data,
          execution.triggered_by,
          parent_execution_id: execution.id,
          retry_count: execution.retry_count + 1
        )

        begin
          executor = build_executor(instance, execution: new_execution, context: context)
          result = executor.execute(execution.input_data || {})

          {
            success: true,
            execution_id: new_execution.id,
            result: result
          }
        rescue Devops::BaseExecutor::ExecutionError => e
          {
            success: false,
            execution_id: new_execution.id,
            error: e.message
          }
        end
      end

      # Cancel a queued or running execution
      def cancel_execution(execution:)
        unless %w[queued running].include?(execution.status)
          return {
            success: false,
            error: "Execution cannot be cancelled (status: #{execution.status})"
          }
        end

        execution.update!(
          status: "cancelled",
          completed_at: Time.current,
          error_message: "Cancelled by user"
        )

        {
          success: true,
          execution_id: execution.id,
          status: "cancelled"
        }
      end

      # Get execution history for an instance
      def execution_history(instance:, filters: {}, page: 1, per_page: 20)
        scope = Devops::IntegrationExecution.where(devops_integration_instance_id: instance.id)

        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.where("created_at >= ?", filters[:since]) if filters[:since].present?
        scope = scope.where("created_at <= ?", filters[:until]) if filters[:until].present?

        scope.order(created_at: :desc)
             .page(page)
             .per(per_page)
      end

      # Get execution statistics for an instance
      def execution_stats(instance:, period: 30.days)
        executions = Devops::IntegrationExecution
          .where(devops_integration_instance_id: instance.id)
          .where("created_at >= ?", period.ago)

        {
          total_executions: executions.count,
          successful: executions.where(status: "completed").count,
          failed: executions.where(status: "failed").count,
          cancelled: executions.where(status: "cancelled").count,
          avg_execution_time_ms: executions.where(status: "completed").average(:execution_time_ms)&.round(2),
          success_rate: calculate_success_rate(executions),
          period_days: period.to_i / 1.day.to_i
        }
      end

      # Bulk execute multiple instances
      def bulk_execute(instances:, input: {}, triggered_by: nil)
        results = instances.map do |instance|
          execute(instance: instance, input: input, triggered_by: triggered_by)
        rescue StandardError => e
          { success: false, instance_id: instance.id, error: e.message }
        end

        {
          total: instances.count,
          successful: results.count { |r| r[:success] },
          failed: results.count { |r| !r[:success] },
          results: results
        }
      end

      private

      def validate_instance!(instance)
        raise InvalidInstanceError, "Instance is nil" unless instance.present?
        raise InvalidInstanceError, "Instance is not active" unless instance.status == "active"
      end

      def create_execution_record(instance, input, triggered_by, options = {})
        Devops::IntegrationExecution.create!(
          devops_integration_instance_id: instance.id,
          account: instance.account,
          status: options[:status] || "running",
          input_data: input,
          triggered_by: triggered_by_string(triggered_by),
          started_at: Time.current,
          parent_execution_id: options[:parent_execution_id],
          retry_count: options[:retry_count] || 0
        )
      end

      def triggered_by_string(triggered_by)
        case triggered_by
        when User
          "user:#{triggered_by.id}"
        when String
          triggered_by
        when Hash
          "#{triggered_by[:type]}:#{triggered_by[:id]}"
        else
          "system"
        end
      end

      def calculate_success_rate(executions)
        total = executions.where(status: %w[completed failed]).count
        return 0.0 if total.zero?

        successful = executions.where(status: "completed").count
        (successful.to_f / total * 100).round(2)
      end
    end
  end
end
