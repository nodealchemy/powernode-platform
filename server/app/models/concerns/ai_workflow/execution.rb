# frozen_string_literal: true

module AiWorkflow::Execution
  extend ActiveSupport::Concern

  # Execution methods
  def execute(input_variables: {}, user: nil, trigger: nil, trigger_type: "manual", trigger_context: {})
    raise ArgumentError, "Workflow is not in a state that can be executed" unless can_execute?

    run_metadata = trigger_context.present? ? { trigger_context: trigger_context } : {}

    # Use database transaction with row-level locking to prevent race conditions
    transaction do
      # Lock this workflow record to prevent concurrent executions
      reload(lock: true)

      # Check for very recent pending/running executions (within last 3 seconds)
      recent_runs = ai_workflow_runs.where(
        "created_at > ? AND status IN (?)",
        3.seconds.ago,
        [ "pending", "running", "initializing" ]
      ).order(:created_at)

      if recent_runs.exists?
        # If there's a very recent pending/running execution, return it instead of creating duplicate
        existing_run = recent_runs.first
        Rails.logger.info "Preventing duplicate execution for workflow #{id}. Recent run exists: #{existing_run.run_id} (created #{Time.current - existing_run.created_at} seconds ago)"
        return existing_run
      end

      run = ai_workflow_runs.build(
        account: account,
        triggered_by_user: user || creator,
        ai_workflow_trigger: trigger,
        trigger_type: trigger_type,
        input_variables: input_variables,
        total_nodes: node_count,
        runtime_context: build_execution_context,
        metadata: run_metadata
      )

      if run.save
        # Queue async execution via worker service API
        begin
          WorkerJobService.enqueue_ai_workflow_execution(run.run_id, {
            "realtime" => true,
            "channel_id" => "ai_workflow_execution_#{run.run_id}"
          })
        rescue StandardError => e
          Rails.logger.error "Failed to enqueue workflow execution: #{e.message}"
          # Still return the run even if enqueueing fails - it can be retried
        end

        update_column(:last_executed_at, Time.current)
        increment!(:execution_count)
        run
      else
        raise ActiveRecord::RecordInvalid, run
      end
    end
  end

  def execution_summary
    recent_runs = ai_workflow_runs.limit(100)

    {
      total_executions: execution_count,
      recent_executions: recent_runs.count,
      success_rate: calculate_success_rate(recent_runs),
      average_duration: calculate_average_duration(recent_runs),
      last_execution: last_executed_at,
      total_cost: recent_runs.sum(:total_cost),
      status_breakdown: recent_runs.group(:status).count
    }
  end

  private

  def build_execution_context
    {
      workflow_version: version,
      node_count: node_count,
      edge_count: edge_count,
      configuration_snapshot: configuration,
      created_at: Time.current.iso8601
    }
  end

  def calculate_success_rate(runs)
    return 0.0 if runs.empty?

    successful = runs.where(status: "completed").count
    (successful.to_f / runs.count * 100).round(2)
  end

  def calculate_average_duration(runs)
    completed_runs = runs.where(status: "completed").where.not(duration_ms: nil)
    return 0 if completed_runs.empty?

    completed_runs.average(:duration_ms).to_i
  end
end
