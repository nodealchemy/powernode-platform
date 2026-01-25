# frozen_string_literal: true

module Ai
  module Workflows
    # Service for managing workflow runs - creation, status updates, and lifecycle operations
    #
    # Consolidates workflow run management logic from WorkflowsController including:
    # - Creating new workflow runs
    # - Updating run status and progress
    # - Cancelling, pausing, and resuming runs
    # - Retrying failed runs
    # - Bulk operations on runs
    #
    # Usage:
    #   service = Ai::Workflows::RunManagementService.new(workflow: @workflow, user: current_user)
    #   result = service.create_run(input_variables: { name: "test" }, trigger_type: "manual")
    #   service.cancel_run(run)
    #
    class RunManagementService
      attr_reader :workflow, :user, :account

      # Initialize the service
      # @param workflow [Ai::Workflow] The workflow to manage runs for
      # @param user [User] The user performing operations
      # @param account [Account] Optional account override (defaults to workflow's account)
      def initialize(workflow:, user:, account: nil)
        @workflow = workflow
        @user = user
        @account = account || workflow.account
      end

      # Create a new workflow run
      # @param input_variables [Hash] Input variables for the run
      # @param trigger_type [String] Type of trigger (manual, schedule, webhook, etc.)
      # @param trigger_context [Hash] Additional trigger context
      # @return [Result] Result object with :success, :run, and :error
      def create_run(input_variables: {}, trigger_type: "manual", trigger_context: {})
        validate_workflow_can_execute!

        run = workflow.runs.build(
          status: "initializing",
          input_variables: input_variables,
          trigger_type: trigger_type,
          trigger_context: trigger_context,
          triggered_by_user: user,
          account: account,
          total_nodes: workflow.nodes.count,
          completed_nodes: 0,
          failed_nodes: 0
        )

        if run.save
          Result.success(run: run)
        else
          Result.failure(error: run.errors.full_messages.join(", "))
        end
      rescue WorkflowExecutionError => e
        Result.failure(error: e.message)
      end

      # Update run status and metadata
      # @param run [Ai::WorkflowRun] The run to update
      # @param attributes [Hash] Attributes to update
      # @return [Result] Result object
      def update_run(run, attributes)
        validate_run_ownership!(run)

        if run.update(sanitize_run_attributes(attributes))
          Result.success(run: run)
        else
          Result.failure(error: run.errors.full_messages.join(", "))
        end
      end

      # Cancel a running workflow
      # @param run [Ai::WorkflowRun] The run to cancel
      # @param reason [String] Optional cancellation reason
      # @return [Result] Result object
      def cancel_run(run, reason: nil)
        validate_run_ownership!(run)

        unless run.can_cancel?
          return Result.failure(error: "Cannot cancel run in status: #{run.status}")
        end

        run.cancel_execution!(reason || "Cancelled by user")
        Result.success(run: run)
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Retry a failed workflow run
      # @param run [Ai::WorkflowRun] The failed run to retry
      # @return [Result] Result object with new run
      def retry_run(run)
        validate_run_ownership!(run)

        unless run.can_retry?
          return Result.failure(error: "Cannot retry run in status: #{run.status}")
        end

        # Create a new run with same inputs
        new_run = workflow.runs.create!(
          status: "initializing",
          input_variables: run.input_variables,
          trigger_type: "retry",
          trigger_context: { original_run_id: run.run_id },
          triggered_by_user: user,
          account: account,
          total_nodes: workflow.nodes.count,
          completed_nodes: 0,
          failed_nodes: 0
        )

        Result.success(run: new_run, original_run: run)
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Pause a running workflow
      # @param run [Ai::WorkflowRun] The run to pause
      # @return [Result] Result object
      def pause_run(run)
        validate_run_ownership!(run)

        unless run.can_pause?
          return Result.failure(error: "Cannot pause run in status: #{run.status}")
        end

        run.pause_execution!
        Result.success(run: run)
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Resume a paused workflow
      # @param run [Ai::WorkflowRun] The run to resume
      # @return [Result] Result object
      def resume_run(run)
        validate_run_ownership!(run)

        unless run.can_resume?
          return Result.failure(error: "Cannot resume run in status: #{run.status}")
        end

        run.resume_execution!
        Result.success(run: run)
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Delete a workflow run
      # @param run [Ai::WorkflowRun] The run to delete
      # @return [Result] Result object
      def delete_run(run)
        validate_run_ownership!(run)

        # Cannot delete running workflows
        if run.status.in?(%w[running initializing])
          return Result.failure(error: "Cannot delete run while it is running")
        end

        run.destroy
        Result.success(message: "Run deleted successfully")
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Bulk delete runs by status
      # @param status [String] Status filter
      # @param before [Time] Optional time filter (delete runs created before this time)
      # @return [Result] Result object with count
      def bulk_delete_runs(status: nil, before: nil)
        runs = workflow.runs

        runs = runs.where(status: status) if status.present?
        runs = runs.where("created_at < ?", before) if before.present?

        # Exclude running workflows
        runs = runs.where.not(status: %w[running initializing])

        deleted_count = runs.count
        runs.destroy_all

        Result.success(deleted_count: deleted_count)
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Check for timeout on a run and its node executions
      # @param run [Ai::WorkflowRun] The run to check
      # @return [Result] Result object with timeout status
      def check_timeout(run)
        validate_run_ownership!(run)

        return Result.success(timed_out: false) unless run.status.in?(%w[running initializing])

        # Check workflow-level timeout
        max_execution_time = workflow.configuration&.dig("max_execution_time") || 3600
        if run.started_at && (Time.current - run.started_at) > max_execution_time
          run.fail_execution!(
            "Workflow exceeded maximum execution time of #{max_execution_time} seconds",
            error_type: "workflow_timeout",
            max_execution_time: max_execution_time,
            execution_duration: (Time.current - run.started_at).to_i
          )
          return Result.success(timed_out: true, reason: "Workflow timeout (#{max_execution_time}s)")
        end

        # Check node-level timeouts
        run.node_executions.where(status: "running").each do |node_exec|
          node = node_exec.node
          timeout_seconds = node.timeout_seconds || 300

          if node_exec.started_at && (Time.current - node_exec.started_at) > timeout_seconds
            node_exec.fail_execution!(
              "Node execution exceeded timeout of #{timeout_seconds} seconds",
              error_type: "node_timeout",
              timeout_seconds: timeout_seconds,
              execution_duration: (Time.current - node_exec.started_at).to_i
            )

            run.update!(failed_nodes: (run.failed_nodes || 0) + 1)
            run.fail_execution!(
              "Workflow failed due to node timeout: #{node.name}",
              error_type: "node_timeout",
              failed_node_id: node.node_id,
              failed_node_name: node.name,
              timeout_seconds: timeout_seconds
            )

            return Result.success(timed_out: true, reason: "Node timeout: #{node.name} (#{timeout_seconds}s)")
          end
        end

        Result.success(timed_out: false)
      rescue StandardError => e
        Result.failure(error: e.message)
      end

      # Get run statistics
      # @return [Hash] Statistics about workflow runs
      def run_statistics
        runs = workflow.runs

        {
          total_runs: runs.count,
          completed_runs: runs.where(status: "completed").count,
          failed_runs: runs.where(status: "failed").count,
          running_runs: runs.where(status: "running").count,
          average_duration: runs.where(status: "completed").average(:duration_ms)&.to_f,
          total_cost: runs.sum(:total_cost).to_f,
          success_rate: calculate_success_rate(runs),
          runs_by_status: runs.group(:status).count,
          runs_by_trigger: runs.group(:trigger_type).count
        }
      end

      private

      def validate_workflow_can_execute!
        unless workflow.can_execute?
          raise WorkflowExecutionError, "Workflow is not in an executable state"
        end
      end

      def validate_run_ownership!(run)
        unless run.workflow_id == workflow.id
          raise WorkflowExecutionError, "Run does not belong to this workflow"
        end
      end

      def sanitize_run_attributes(attributes)
        permitted = %i[
          status started_at completed_at cancelled_at
          failed_nodes completed_nodes total_cost duration_ms
          output_variables runtime_context error_details metadata
        ]

        attributes.slice(*permitted)
      end

      def calculate_success_rate(runs)
        total = runs.where.not(status: %w[running initializing pending]).count
        return nil if total.zero?

        completed = runs.where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      # Result wrapper for service operations
      class Result
        attr_reader :success, :data

        def initialize(success:, data: {})
          @success = success
          @data = data
        end

        def self.success(data = {})
          new(success: true, data: data)
        end

        def self.failure(data = {})
          new(success: false, data: data)
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def method_missing(method, *args, &block)
          if data.key?(method)
            data[method]
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          data.key?(method) || super
        end
      end

      # Custom error class for workflow execution errors
      class WorkflowExecutionError < StandardError; end
    end
  end
end
