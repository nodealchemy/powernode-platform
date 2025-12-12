# frozen_string_literal: true

class AiWorkflowRun < ApplicationRecord
  # Authentication & Authorization
  belongs_to :ai_workflow
  belongs_to :account
  belongs_to :triggered_by_user, class_name: "User", optional: true
  belongs_to :ai_workflow_trigger, optional: true

  # Associations
  has_many :ai_workflow_node_executions, dependent: :destroy
  alias_method :node_executions, :ai_workflow_node_executions
  has_many :ai_workflow_run_logs, dependent: :destroy
  has_many :ai_workflow_checkpoints, dependent: :destroy
  has_many :ai_agent_messages, dependent: :destroy
  has_many :ai_shared_context_pools, dependent: :destroy
  has_many :ai_workflow_compensations, dependent: :destroy

  # Accessor methods for data stored in metadata
  def trigger_context
    metadata["trigger_context"] || {}
  end

  def trigger_context=(context)
    self.metadata = (metadata || {}).merge("trigger_context" => context)
  end

  # Validations
  validates :run_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: {
    in: %w[initializing running completed failed cancelled waiting_approval],
    message: "must be a valid run status"
  }
  validates :trigger_type, presence: true, inclusion: {
    in: %w[manual webhook schedule event api_call],
    message: "must be a valid trigger type"
  }
  validates :total_nodes, numericality: { greater_than_or_equal_to: 0 }
  validates :completed_nodes, numericality: { greater_than_or_equal_to: 0 }
  validates :failed_nodes, numericality: { greater_than_or_equal_to: 0 }
  validates :total_cost, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_node_progress_consistency
  validate :validate_execution_times

  # JSON columns
  attribute :input_variables, :json, default: -> { {} }
  attribute :output_variables, :json, default: -> { {} }
  attribute :runtime_context, :json, default: -> { {} }
  attribute :error_details, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: %w[initializing running waiting_approval]) }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :stale, -> { where(status: %w[initializing running]).where("created_at < ?", 30.minutes.ago) }
  scope :find_by_partial_id, ->(partial_id) { where("id::text LIKE ?", "%#{sanitize_sql_like(partial_id)}%") }

  # Callbacks for real-time broadcasting
  after_update :broadcast_status_change, if: :saved_change_to_status?
  after_update :broadcast_progress_change, if: -> { saved_change_to_completed_nodes? || saved_change_to_failed_nodes? }
  after_update :broadcast_duration_update, if: -> { running? && !saved_change_to_status? && !saved_change_to_completed_nodes? && !saved_change_to_failed_nodes? }
  after_create :broadcast_execution_started
  after_update :broadcast_execution_completed, if: -> { saved_change_to_status? && status == "completed" }
  after_update :copy_variables_to_output, if: -> { saved_change_to_status? && status == "completed" }
  after_update :broadcast_execution_failed, if: -> { saved_change_to_status? && status == "failed" }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :finished, -> { where(status: %w[completed failed cancelled]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_trigger_type, ->(type) { where(trigger_type: type) }
  scope :by_status, ->(status) { where(status: status) }
  scope :for_workflow, ->(workflow_id) { where(ai_workflow_id: workflow_id) }
  scope :for_user, ->(user_id) { where(triggered_by_user_id: user_id) }
  scope :with_cost, -> { where("total_cost > 0") }

  # Callbacks
  before_validation :generate_run_id, on: :create
  before_validation :set_initial_values, on: :create
  after_create :log_workflow_started
  after_create :schedule_timeout_check
  after_update :log_status_changes, if: :saved_change_to_status?
  after_update :calculate_duration, if: :saved_change_to_completed_at?

  # Status check methods
  def initializing?
    status == "initializing"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  def waiting_for_approval?
    status == "waiting_approval"
  end

  def active?
    %w[initializing running waiting_approval].include?(status)
  end

  def finished?
    %w[completed failed cancelled].include?(status)
  end

  def successful?
    completed? && failed_nodes == 0
  end

  # Execution control methods
  def start_execution!
    return false unless initializing?

    update!(
      status: "running",
      started_at: Time.current,
      metadata: metadata.merge("execution_started_at" => Time.current.iso8601)
    )
  end

  def complete_execution!(output_vars = {})
    return false unless running?

    # Merge runtime_context variables into output_variables for workflow output display
    runtime_variables = runtime_context["variables"] || {}
    final_output_vars = output_variables.merge(runtime_variables).merge(output_vars)

    update!(
      status: "completed",
      completed_at: Time.current,
      output_variables: final_output_vars,
      metadata: metadata.merge("execution_completed_at" => Time.current.iso8601)
    )
  end

  def fail_execution!(error_message, error_details_hash = {})
    current_time = Time.current

    # Prepare update attributes
    update_attrs = {
      status: "failed",
      completed_at: current_time,
      error_details: error_details.merge({
        "error_message" => error_message,
        "failed_at" => current_time.iso8601
      }.merge(error_details_hash)),
      metadata: metadata.merge("execution_failed_at" => current_time.iso8601)
    }

    # Ensure started_at is set to satisfy validation (completed_at must be after started_at)
    if started_at.nil?
      # Set started_at to 1 second before completed_at
      update_attrs[:started_at] = current_time - 1.second
      Rails.logger.warn "[AI_WORKFLOW_RUN] Workflow run #{run_id} failed before starting - setting started_at retroactively"
    end

    update!(update_attrs)
  end

  def cancel_execution!(reason = "User cancelled")
    return false if finished?

    transaction do
      # Cancel any pending/running node executions
      ai_workflow_node_executions
        .where(status: %w[pending running waiting_approval])
        .update_all(
          status: "cancelled",
          cancelled_at: Time.current,
          error_details: { "cancellation_reason" => reason }.to_json
        )

      update!(
        status: "cancelled",
        cancelled_at: Time.current,
        completed_at: Time.current,
        error_details: error_details.merge({
          "cancellation_reason" => reason,
          "cancelled_at" => Time.current.iso8601
        }),
        metadata: metadata.merge("execution_cancelled_at" => Time.current.iso8601)
      )
    end

    true
  end

  # Alias for controller compatibility
  def cancel!(reason: "User cancelled", cancelled_by: nil)
    cancel_execution!(reason)
  end

  def pause_for_approval!(approval_node_id, approval_message)
    return false unless running?

    update!(
      status: "waiting_approval",
      metadata: metadata.merge({
        "approval_node_id" => approval_node_id,
        "approval_message" => approval_message,
        "approval_requested_at" => Time.current.iso8601
      })
    )
  end

  def resume_after_approval!(approved_by_user_id, approval_decision)
    return false unless waiting_for_approval?

    update!(
      status: "running",
      metadata: metadata.merge({
        "approval_decision" => approval_decision,
        "approved_by" => approved_by_user_id,
        "approval_completed_at" => Time.current.iso8601
      })
    )
  end

  # Progress tracking methods
  def progress_percentage
    return 0 if total_nodes == 0
    return 100 if completed?

    (completed_nodes.to_f / total_nodes * 100).round(2)
  end

  def execution_progress
    {
      percentage: progress_percentage,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      pending_nodes: total_nodes - completed_nodes - failed_nodes,
      total_nodes: total_nodes,
      current_status: status
    }
  end

  def update_progress!
    # CRITICAL FIX: Use thread-local storage for re-entry protection
    progress_key = "updating_workflow_progress_#{id}"

    return if Thread.current[progress_key]

    Thread.current[progress_key] = true

    begin
      node_executions = ai_workflow_node_executions

      # Calculate new progress values
      new_completed = node_executions.where(status: %w[completed skipped]).count
      new_failed = node_executions.where(status: "failed").count

      # Only update if values have changed
      if completed_nodes != new_completed || failed_nodes != new_failed
        update!(
          completed_nodes: new_completed,
          failed_nodes: new_failed
        )
      end
    ensure
      Thread.current[progress_key] = nil
    end
  end

  # Duration and timing methods
  def execution_duration
    return nil unless started_at

    end_time = completed_at || cancelled_at || Time.current
    end_time - started_at
  end

  def execution_duration_seconds
    execution_duration&.to_i
  end

  def execution_time_ms
    return duration_ms if duration_ms.present?
    return nil unless execution_duration

    (execution_duration * 1000).to_i
  end

  # Alias method for backward compatibility
  alias_method :execution_duration_ms, :execution_time_ms

  def time_since_start
    return nil unless started_at

    Time.current - started_at
  end

  def estimated_completion_time
    return nil unless running? && started_at && total_nodes > 0 && completed_nodes > 0

    avg_time_per_node = time_since_start / completed_nodes
    remaining_nodes = total_nodes - completed_nodes

    Time.current + (avg_time_per_node * remaining_nodes)
  end

  # Variable management
  def get_variable(name)
    runtime_context.dig("variables", name.to_s) ||
    input_variables[name.to_s] ||
    input_variables[name.to_sym]
  end

  def set_variable(name, value)
    variables = runtime_context["variables"] || {}
    variables[name.to_s] = value

    update!(
      runtime_context: runtime_context.merge("variables" => variables)
    )
  end

  def merge_variables(new_variables)
    return if new_variables.blank?

    current_variables = runtime_context["variables"] || {}
    merged_variables = current_variables.merge(new_variables.stringify_keys)

    update!(
      runtime_context: runtime_context.merge("variables" => merged_variables)
    )
  end

  # Node execution management
  def create_node_execution(workflow_node, input_data = {})
    # Check if node execution already exists for this node in this run
    existing_execution = ai_workflow_node_executions.find_by(node_id: workflow_node.node_id)

    if existing_execution
      Rails.logger.info "Node execution already exists for node #{workflow_node.node_id} in run #{run_id}, returning existing execution"
      return existing_execution
    end

    ai_workflow_node_executions.create!(
      ai_workflow_node: workflow_node,
      node_id: workflow_node.node_id,
      node_type: workflow_node.node_type,
      input_data: input_data,
      configuration_snapshot: workflow_node.configuration,
      execution_id: SecureRandom.uuid,
      max_retries: workflow_node.retry_count || 0,
      metadata: {
        "created_for_run" => run_id,
        "workflow_version" => ai_workflow.version
      }
    )
  end

  def get_node_execution(node_id)
    ai_workflow_node_executions.find_by(node_id: node_id)
  end

  def node_execution_status(node_id)
    execution = get_node_execution(node_id)
    execution&.status || "not_started"
  end

  # Cost tracking
  def add_cost(amount, source = "node_execution")
    return unless amount.present? && amount > 0

    # CRITICAL FIX: Use thread-local storage for re-entry protection
    cost_key = "adding_workflow_cost_#{id}"

    return if Thread.current[cost_key]

    Thread.current[cost_key] = true

    begin
      increment!(:total_cost, amount)

      # Log cost addition
      ai_workflow_run_logs.create!(
        log_level: "info",
        event_type: "cost_added",
        message: "Added cost: $#{amount} from #{source}",
        context_data: {
          "amount" => amount,
          "source" => source,
          "total_cost" => total_cost + amount
        }
      )
    ensure
      Thread.current[cost_key] = nil
    end
  end

  def cost_breakdown
    node_costs = ai_workflow_node_executions.where("cost > 0").pluck(:node_id, :cost)

    {
      total_cost: total_cost,
      node_costs: node_costs.to_h,
      cost_per_node: node_costs.any? ? total_cost / node_costs.size : 0
    }
  end

  # Logging methods
  def log(level, event_type, message, context = {}, node_execution = nil)
    ai_workflow_run_logs.create!(
      ai_workflow_node_execution: node_execution,
      log_level: level.to_s,
      event_type: event_type.to_s,
      message: message,
      context_data: context,
      node_id: node_execution&.node_id,
      source: "workflow_run",
      logged_at: Time.current
    )
  end

  def log_info(event_type, message, context = {})
    log("info", event_type, message, context)
  end

  def log_error(event_type, message, context = {})
    log("error", event_type, message, context)
  end

  def log_warning(event_type, message, context = {})
    log("warn", event_type, message, context)
  end

  # Run summary and analysis
  def execution_summary
    {
      run_id: run_id,
      workflow_name: ai_workflow.name,
      status: status,
      trigger_type: trigger_type,
      progress: execution_progress,
      duration_seconds: execution_duration_seconds,
      cost: {
        total: total_cost,
        breakdown: cost_breakdown
      },
      timestamps: {
        created: created_at,
        started: started_at,
        completed: completed_at,
        cancelled: cancelled_at
      },
      node_summary: node_execution_summary,
      error_summary: error_details.present? ? error_details : nil
    }
  end

  def node_execution_summary
    executions = ai_workflow_node_executions.includes(:ai_workflow_node)

    {
      total: executions.count,
      by_status: executions.group(:status).count,
      by_type: executions.joins(:ai_workflow_node).group("ai_workflow_nodes.node_type").count,
      average_duration: executions.where(status: "completed").average(:duration_ms)&.to_i || 0,
      total_cost: executions.sum(:cost)
    }
  end

  # Retry and recovery
  def can_retry?
    failed? && ai_workflow.can_execute?
  end

  def can_cancel?
    active?
  end

  def can_pause?
    running?
  end

  def can_resume?
    status == "paused"
  end

  def retry_execution!(user = nil)
    return false unless can_retry?

    new_run = ai_workflow.execute(
      input_variables,
      user: user || triggered_by_user,
      trigger: ai_workflow_trigger,
      trigger_type: "manual"
    )

    # Link to original run
    new_run.update!(
      metadata: new_run.metadata.merge({
        "retried_from" => run_id,
        "original_run_id" => run_id,
        "retry_attempt" => (metadata["retry_attempt"] || 0) + 1
      })
    )

    new_run
  end

  # Alias for controller compatibility
  def retry!(retry_options: {}, triggered_by: nil)
    retry_execution!(triggered_by)
  end

  # Calculate execution metrics for the workflow run
  def calculate_execution_metrics
    node_executions = ai_workflow_node_executions

    {
      total_nodes: ai_workflow.ai_workflow_nodes.count,
      completed_nodes: node_executions.where(status: "completed").count,
      failed_nodes: node_executions.where(status: "failed").count,
      running_nodes: node_executions.where(status: "running").count,
      duration_ms: duration_ms || 0,
      total_cost: total_cost || 0,
      status: status
    }
  end

  private

  def copy_variables_to_output
    # Copy runtime_context variables to output_variables for display
    if runtime_context["variables"].present? && output_variables.empty?
      update_column(:output_variables, runtime_context["variables"])
    end
  end

  def broadcast_status_change
    # Prepare common workflow run data
    workflow_run_data = {
      id: id,
      run_id: run_id,
      ai_workflow_id: ai_workflow_id,
      status: status,
      trigger_type: trigger_type,
      started_at: started_at,
      completed_at: completed_at,
      created_at: created_at,
      duration_seconds: execution_duration_seconds || (started_at ? (Time.current - started_at).to_i : nil),
      total_nodes: total_nodes,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      cost_usd: total_cost,
      output_variables: output_variables,  # Include for preview modal
      error_details: error_details,
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel (for workflow execution modal)
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.run.status.changed",
      self,
      {
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {}
      }
    )

    # Broadcast to workflow-level channel (for workflow history updates)
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_run_status_changed",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_progress_change
    # Broadcast progress updates without status change
    workflow_run_data = {
      id: id,
      run_id: run_id,
      ai_workflow_id: ai_workflow_id,
      status: status,
      trigger_type: trigger_type,
      started_at: started_at,
      completed_at: completed_at,
      created_at: created_at,
      duration_seconds: execution_duration_seconds || (started_at ? (Time.current - started_at).to_i : nil),
      total_nodes: total_nodes,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      cost_usd: total_cost,
      output_variables: output_variables,  # Include for preview modal
      error_details: error_details,
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel (for workflow execution modal)
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.run.progress.changed",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "progress_changed"
      }
    )

    # Broadcast to workflow-level channel (for workflow history updates)
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_progress_changed",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_duration_update
    # Broadcast live duration updates for running workflows
    return unless running? && started_at

    workflow_run_data = {
      id: id,
      run_id: run_id,
      ai_workflow_id: ai_workflow_id,
      status: status,
      trigger_type: trigger_type,
      started_at: started_at,
      completed_at: completed_at,
      created_at: created_at,
      duration_seconds: (Time.current - started_at).to_i,  # Always live duration for running workflows
      total_nodes: total_nodes,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      cost_usd: total_cost,
      output_variables: output_variables,  # Include for preview modal
      error_details: error_details,
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel (for workflow execution modal)
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.run.duration.updated",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "duration_update"
      }
    )

    # Broadcast to workflow-level channel (for workflow history updates)
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_duration_update",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )

    Rails.logger.debug "[AI_WORKFLOW_RUN] Duration update broadcast sent for run #{run_id}: #{workflow_run_data[:duration_seconds]}s"
  end

  # Public method to manually trigger duration updates (can be called from external services)
  def broadcast_live_duration!
    broadcast_duration_update if running?
  end

  def broadcast_execution_started
    workflow_run_data = {
      id: id,
      run_id: run_id,
      workflow_id: ai_workflow_id,
      trigger_type: trigger_type,
      status: status,
      started_at: started_at,
      total_nodes: total_nodes
    }

    # Broadcast to run-specific channel
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.execution.started",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "execution_started"
      }
    )

    # Broadcast to workflow-level channel
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_execution_started",
        workflow_run: workflow_run_data,
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_execution_completed
    workflow_run_data = {
      id: id,
      run_id: run_id,
      workflow_id: ai_workflow_id,
      trigger_type: trigger_type,
      status: status,
      completed_at: completed_at,
      duration_seconds: execution_duration_seconds,
      completed_nodes: completed_nodes,
      failed_nodes: failed_nodes,
      cost_usd: total_cost,
      output_variables: output_variables,  # Include for preview modal
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.execution.completed",
      self,
      {
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        event_type: "execution_completed"
      }
    )

    # Broadcast to workflow-level channel
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_execution_completed",
        workflow_run: workflow_run_data,
        workflow_stats: ai_workflow.respond_to?(:stats) ? ai_workflow.stats : {},
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_execution_failed
    workflow_run_data = {
      id: id,
      run_id: run_id,
      workflow_id: ai_workflow_id,
      trigger_type: trigger_type,
      status: status,
      output_variables: output_variables,  # Include for preview modal
      error_details: error_details,
      failed_at: completed_at,
      duration_seconds: execution_duration_seconds,
      progress_percentage: progress_percentage
    }

    # Broadcast to run-specific channel
    AiOrchestrationChannel.broadcast_workflow_run_event(
      "workflow.execution.failed",
      self,
      {
        workflow_run: workflow_run_data,
        event_type: "execution_failed"
      }
    )

    # Broadcast to workflow-level channel
    ActionCable.server.broadcast(
      "workflow_#{ai_workflow_id}",
      {
        type: "workflow_execution_failed",
        workflow_run: workflow_run_data,
        timestamp: Time.current.iso8601
      }
    )
  end

  def generate_run_id
    self.run_id = UUID7.generate if run_id.blank?
  end

  def set_initial_values
    return unless new_record?
    return unless ai_workflow.present?

    self.total_nodes = ai_workflow.ai_workflow_nodes.count
    self.completed_nodes = 0
    self.failed_nodes = 0
    self.total_cost = 0.0

    if runtime_context.blank?
      self.runtime_context = {
        "variables" => {},
        "execution_context" => {
          "workflow_version" => ai_workflow.version,
          "created_at" => Time.current.iso8601
        }
      }
    end
  end

  def validate_node_progress_consistency
    return unless total_nodes.present? && completed_nodes.present? && failed_nodes.present?

    if completed_nodes + failed_nodes > total_nodes
      errors.add(:base, "Sum of completed and failed nodes cannot exceed total nodes")
    end

    if completed_nodes < 0 || failed_nodes < 0
      errors.add(:base, "Node counts cannot be negative")
    end
  end

  def validate_execution_times
    # Validate time ordering when both are present
    if started_at.present? && completed_at.present? && completed_at < started_at
      errors.add(:completed_at, "must be after started_at")
    end

    # Validate required timestamps for completed status
    if status == "completed" && completed_at.blank?
      errors.add(:completed_at, "can't be blank for completed runs")
    end

    # Validate required timestamps for failed status
    if status == "failed" && completed_at.blank?
      errors.add(:completed_at, "can't be blank for failed runs")
    end

    # Validate required error_details for failed status
    if status == "failed" && (error_details.blank? || error_details.empty?)
      errors.add(:error_details, "can't be blank for failed runs")
    end

    # Validate required timestamps for cancelled status
    if status == "cancelled" && cancelled_at.blank?
      errors.add(:cancelled_at, "can't be blank for cancelled runs")
    end
  end

  def log_workflow_started
    log_info("workflow_started", "Workflow run started: #{ai_workflow.name}", {
      "workflow_id" => ai_workflow_id,
      "trigger_type" => trigger_type,
      "input_variables" => input_variables.keys
    })
  end

  def log_status_changes
    old_status = saved_change_to_status[0]
    new_status = saved_change_to_status[1]

    # Map status changes to valid workflow event types
    event_type = case new_status
    when "completed"
      "workflow_completed"
    when "failed"
      "workflow_failed"
    when "cancelled"
      "workflow_cancelled"
    when "running"
      "workflow_started"
    else
      "workflow_started" # fallback
    end

    log_info(event_type, "Workflow status changed from #{old_status} to #{new_status}", {
      "old_status" => old_status,
      "new_status" => new_status,
      "progress_percentage" => progress_percentage
    })
  end

  def calculate_duration
    return unless started_at && completed_at

    # Ensure positive duration - handle edge cases where completed_at < started_at
    duration_seconds = completed_at - started_at
    calculated_duration_ms = [ duration_seconds * 1000, 0 ].max.to_i

    # Use update_column to avoid triggering callbacks (prevents stack overflow)
    if duration_ms != calculated_duration_ms
      update_column(:duration_ms, calculated_duration_ms)
    end
  end

  # Timeout management methods
  def schedule_timeout_check
    # Schedule automatic timeout for stuck workflows via worker service
    return unless Rails.env.development? || Rails.env.production?

    begin
      # Use WorkerJobService to queue the timeout job in the worker service
      WorkerJobService.new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "WorkflowTimeoutJob",
        "args" => [ run_id ],
        "queue" => "maintenance",
        "at" => 30.minutes.from_now.to_i
      })
    rescue => e
      Rails.logger.warn "Failed to schedule timeout job for workflow run #{run_id}: #{e.message}"
    end
  end

  def check_and_handle_timeout
    return unless active?

    # Check if workflow has been stuck in initializing state > 15 minutes
    if initializing? && created_at < 15.minutes.ago
      cancel_execution!("Automatic timeout - stuck in initializing state for #{((Time.current - created_at) / 60).round(1)} minutes")
      Rails.logger.warn "Auto-cancelled stuck initializing workflow: #{run_id}"
      return true
    end

    # Check if workflow has been running with no progress > 45 minutes
    if running? && started_at && started_at < 45.minutes.ago && completed_nodes <= 1
      cancel_execution!("Automatic timeout - no progress for #{((Time.current - started_at) / 60).round(1)} minutes")
      Rails.logger.warn "Auto-cancelled stuck running workflow: #{run_id}"
      return true
    end

    false
  end

  def has_timeout_job?
    # Check if timeout job already exists (optional - for debugging)
    return false unless defined?(Sidekiq)

    begin
      scheduled_jobs = Sidekiq::ScheduledSet.new
      scheduled_jobs.any? { |job| job.klass == "WorkflowTimeoutJob" && job.args.include?(id) }
    rescue
      false
    end
  end
end
