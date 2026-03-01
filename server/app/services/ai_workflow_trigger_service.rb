# frozen_string_literal: true

# AiWorkflowTriggerService - Manages workflow triggers and scheduled executions
#
# This service handles the registration and execution of workflow triggers,
# including scheduled triggers, event-based triggers, and manual triggers.
#
# Usage:
#   trigger_service = AiWorkflowTriggerService.instance
#   trigger_service.register_trigger(workflow, trigger_config)
#   trigger_service.fire_trigger(trigger_id)
#
class AiWorkflowTriggerService
  include Singleton

  # Supported trigger types
  TRIGGER_TYPES = {
    "manual" => { description: "Manually triggered workflow", requires_schedule: false },
    "schedule" => { description: "Time-based scheduled trigger", requires_schedule: true },
    "event" => { description: "Event-based trigger", requires_schedule: false },
    "webhook" => { description: "External webhook trigger", requires_schedule: false },
    "api" => { description: "API call trigger", requires_schedule: false }
  }.freeze

  def initialize
    @registered_triggers = {}
    @scheduled_jobs = {}
    @mutex = Mutex.new
    @running = false
    @stats = {
      triggers_registered: 0,
      triggers_fired: 0,
      triggers_failed: 0,
      last_trigger_at: nil
    }
  end

  # Start the trigger service
  def start
    @mutex.synchronize do
      return if @running

      @running = true
      load_active_triggers
      Rails.logger.info "[TriggerService] Started with #{@registered_triggers.count} triggers"
    end
  end

  # Stop the trigger service
  def stop
    @mutex.synchronize do
      return unless @running

      @running = false
      cancel_all_scheduled_jobs
      Rails.logger.info "[TriggerService] Stopped"
    end
  end

  # Get service status
  #
  # @return [Hash] Service status information
  def status
    @mutex.synchronize do
      {
        running: @running,
        registered_triggers: @registered_triggers.count,
        scheduled_jobs: @scheduled_jobs.count,
        stats: @stats.dup
      }
    end
  end

  # Register a trigger for a workflow
  #
  # @param workflow [Ai::Workflow] The workflow to trigger
  # @param config [Hash] Trigger configuration
  # @return [String] Trigger ID
  def register_trigger(workflow, config = {})
    trigger_id = SecureRandom.uuid
    trigger_type = config[:type] || config["type"] || "manual"

    trigger = {
      id: trigger_id,
      workflow_id: workflow.id,
      workflow_name: workflow.name,
      account_id: workflow.account_id,
      type: trigger_type,
      config: config,
      enabled: true,
      created_at: Time.current,
      last_fired_at: nil,
      fire_count: 0
    }

    @mutex.synchronize do
      @registered_triggers[trigger_id] = trigger
      @stats[:triggers_registered] += 1
    end

    # Set up scheduled job if needed
    if trigger_type == "schedule" && config[:schedule].present?
      schedule_trigger(trigger_id, config[:schedule])
    end

    Rails.logger.info "[TriggerService] Registered trigger: #{trigger_id} for workflow #{workflow.name}"
    trigger_id
  end

  # Unregister a trigger
  #
  # @param trigger_id [String] The trigger ID to remove
  def unregister_trigger(trigger_id)
    @mutex.synchronize do
      trigger = @registered_triggers.delete(trigger_id)
      cancel_scheduled_job(trigger_id) if trigger

      Rails.logger.info "[TriggerService] Unregistered trigger: #{trigger_id}" if trigger
    end
  end

  # Fire a trigger to start workflow execution
  #
  # @param trigger_id [String] The trigger to fire
  # @param input_data [Hash] Input data for the workflow
  # @param user [User] The user initiating the trigger (optional)
  # @return [Hash] Result of the trigger firing
  def fire_trigger(trigger_id, input_data = {}, user = nil)
    trigger = @mutex.synchronize { @registered_triggers[trigger_id]&.dup }

    unless trigger
      Rails.logger.warn "[TriggerService] Trigger not found: #{trigger_id}"
      return { success: false, error: "Trigger not found" }
    end

    unless trigger[:enabled]
      Rails.logger.warn "[TriggerService] Trigger disabled: #{trigger_id}"
      return { success: false, error: "Trigger is disabled" }
    end

    begin
      workflow = Ai::Workflow.find(trigger[:workflow_id])

      unless workflow.active?
        return { success: false, error: "Workflow is not active" }
      end

      # Determine which user to use for execution
      execution_user = user || find_system_user(trigger[:account_id])

      # Start workflow execution
      result = start_workflow_execution(workflow, input_data, execution_user, trigger)

      # Update trigger stats
      @mutex.synchronize do
        @registered_triggers[trigger_id][:last_fired_at] = Time.current
        @registered_triggers[trigger_id][:fire_count] += 1
        @stats[:triggers_fired] += 1
        @stats[:last_trigger_at] = Time.current
      end

      # Dispatch trigger event
      AiWorkflowEventDispatcherService.instance.dispatch_event(
        "workflow.trigger.fired",
        {
          trigger_id: trigger_id,
          workflow_id: workflow.id,
          workflow_run_id: result[:workflow_run_id],
          trigger_type: trigger[:type]
        }
      )

      Rails.logger.info "[TriggerService] Fired trigger #{trigger_id} for workflow #{workflow.name}"

      {
        success: true,
        trigger_id: trigger_id,
        workflow_id: workflow.id,
        workflow_run_id: result[:workflow_run_id]
      }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "[TriggerService] Workflow not found for trigger #{trigger_id}: #{e.message}"
      @mutex.synchronize { @stats[:triggers_failed] += 1 }
      { success: false, error: "Workflow not found" }
    rescue StandardError => e
      Rails.logger.error "[TriggerService] Error firing trigger #{trigger_id}: #{e.message}"
      @mutex.synchronize { @stats[:triggers_failed] += 1 }
      { success: false, error: e.message }
    end
  end

  # Fire a trigger by workflow ID
  #
  # @param workflow_id [String] The workflow ID
  # @param input_data [Hash] Input data for the workflow
  # @param user [User] The user initiating the execution
  # @return [Hash] Result of the execution
  def fire_by_workflow(workflow_id, input_data = {}, user = nil)
    # Find or create a manual trigger for the workflow
    trigger_id = find_trigger_by_workflow(workflow_id) || create_manual_trigger(workflow_id)

    return { success: false, error: "Could not create trigger" } unless trigger_id

    fire_trigger(trigger_id, input_data, user)
  end

  # Enable a trigger
  #
  # @param trigger_id [String] The trigger ID
  def enable_trigger(trigger_id)
    @mutex.synchronize do
      trigger = @registered_triggers[trigger_id]
      return false unless trigger

      trigger[:enabled] = true
      true
    end
  end

  # Disable a trigger
  #
  # @param trigger_id [String] The trigger ID
  def disable_trigger(trigger_id)
    @mutex.synchronize do
      trigger = @registered_triggers[trigger_id]
      return false unless trigger

      trigger[:enabled] = false
      cancel_scheduled_job(trigger_id)
      true
    end
  end

  # Get all triggers for a workflow
  #
  # @param workflow_id [String] The workflow ID
  # @return [Array<Hash>] List of triggers
  def triggers_for_workflow(workflow_id)
    @mutex.synchronize do
      @registered_triggers.values.select { |t| t[:workflow_id] == workflow_id }
    end
  end

  # Get trigger by ID
  #
  # @param trigger_id [String] The trigger ID
  # @return [Hash, nil] Trigger data or nil
  def get_trigger(trigger_id)
    @mutex.synchronize do
      @registered_triggers[trigger_id]&.dup
    end
  end

  private

  def load_active_triggers
    # Load triggers from active workflows
    Ai::Workflow.where(is_active: true).find_each do |workflow|
      trigger_config = workflow.trigger_config || {}

      if trigger_config.present?
        register_trigger(workflow, trigger_config.with_indifferent_access)
      else
        # Register a default manual trigger
        register_trigger(workflow, { type: "manual" })
      end
    end
  rescue StandardError => e
    Rails.logger.error "[TriggerService] Error loading triggers: #{e.message}"
  end

  def schedule_trigger(trigger_id, schedule_config)
    # For now, use a simple approach - in production, use Sidekiq scheduled jobs
    # This is a placeholder for proper cron-style scheduling
    Rails.logger.info "[TriggerService] Schedule configured for trigger #{trigger_id}: #{schedule_config}"
  end

  def cancel_scheduled_job(trigger_id)
    job = @scheduled_jobs.delete(trigger_id)
    # Cancel the job if it exists
  end

  def cancel_all_scheduled_jobs
    @scheduled_jobs.each_key do |trigger_id|
      cancel_scheduled_job(trigger_id)
    end
    @scheduled_jobs.clear
  end

  def start_workflow_execution(workflow, input_data, user, trigger)
    account = workflow.account

    # Create a workflow run
    workflow_run = workflow.workflow_runs.create!(
      account: account,
      user: user,
      status: "pending",
      run_id: SecureRandom.uuid,
      input_variables: input_data,
      total_nodes: workflow.workflow_nodes.count,
      metadata: {
        trigger_id: trigger[:id],
        trigger_type: trigger[:type],
        triggered_at: Time.current.iso8601
      }
    )

    # Start the workflow execution using the orchestrator
    if defined?(Mcp::AiWorkflowOrchestrator)
      orchestrator = Mcp::AiWorkflowOrchestrator.new(
        workflow: workflow,
        workflow_run: workflow_run,
        input_variables: input_data,
        account: account
      )

      # Execute asynchronously
      Thread.new do
        orchestrator.execute
      rescue StandardError => e
        Rails.logger.error "[TriggerService] Orchestrator error: #{e.message}"
      end
    else
      # Fallback to event-based execution
      workflow_run.update!(status: "running", started_at: Time.current)

      AiWorkflowEventDispatcherService.instance.dispatch_event(
        "workflow.execution.started",
        {
          workflow_id: workflow.id,
          workflow_run_id: workflow_run.id,
          run_id: workflow_run.run_id,
          input: input_data
        }
      )
    end

    { workflow_run_id: workflow_run.id, run_id: workflow_run.run_id }
  end

  def find_trigger_by_workflow(workflow_id)
    @mutex.synchronize do
      trigger = @registered_triggers.values.find { |t| t[:workflow_id] == workflow_id }
      trigger&.dig(:id)
    end
  end

  def create_manual_trigger(workflow_id)
    workflow = Ai::Workflow.find_by(id: workflow_id)
    return nil unless workflow

    register_trigger(workflow, { type: "manual" })
  rescue StandardError => e
    Rails.logger.error "[TriggerService] Error creating manual trigger: #{e.message}"
    nil
  end

  def find_system_user(account_id)
    # Find a system user or the first admin user for the account
    account = Account.find_by(id: account_id)
    return nil unless account

    # Try to find a system user first
    system_user = account.users.joins(:roles).where(roles: { name: "system" }).first

    # Fall back to admin user
    system_user || account.users.joins(:roles).where(roles: { name: "admin" }).first
  end
end
