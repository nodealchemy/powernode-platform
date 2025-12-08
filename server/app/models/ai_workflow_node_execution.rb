# frozen_string_literal: true

class AiWorkflowNodeExecution < ApplicationRecord
  # Authentication & Authorization
  belongs_to :ai_workflow_run
  belongs_to :ai_workflow_node
  belongs_to :ai_agent_execution, optional: true

  # Associations
  has_many :ai_workflow_run_logs, dependent: :destroy
  delegate :account, to: :ai_workflow_run
  delegate :ai_workflow, to: :ai_workflow_run

  # Validations
  validates :execution_id, presence: true, uniqueness: true
  validates :node_id, presence: true
  validates :node_type, presence: true
  validates :status, presence: true, inclusion: { 
    in: %w[pending running completed failed cancelled skipped waiting_approval],
    message: 'must be a valid execution status'
  }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
  validates :max_retries, numericality: { greater_than_or_equal_to: 0 }
  validates :cost, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_retry_limits

  # JSON columns
  attribute :input_data, :json, default: -> { {} }
  attribute :output_data, :json, default: -> { {} }
  attribute :configuration_snapshot, :json, default: -> { {} }
  attribute :error_details, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :skipped, -> { where(status: 'skipped') }
  scope :waiting_approval, -> { where(status: 'waiting_approval') }
  scope :active, -> { where(status: %w[pending running waiting_approval]) }
  scope :finished, -> { where(status: %w[completed failed cancelled skipped]) }
  scope :successful, -> { where(status: %w[completed skipped]) }
  scope :by_node_type, ->(type) { where(node_type: type) }
  scope :with_cost, -> { where('cost > 0') }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :generate_execution_id, on: :create
  after_create :log_node_execution_started
  after_update :log_status_changes, if: :saved_change_to_status?
  after_update :calculate_duration, if: :saved_change_to_completed_at?
  # CRITICAL FIX: Remove callbacks that trigger nested update! calls
  # These cause stack overflow when called during node completion
  # The orchestrator will call these methods explicitly after node completion
  # after_update :update_run_progress, if: :saved_change_to_status?
  # after_update :add_cost_to_run, if: :saved_change_to_cost?

  # CRITICAL FIX: Use after_commit with instance variable tracking
  # ActiveRecord clears saved_changes after update, so we track status changes manually
  after_commit :broadcast_node_status_change_if_needed, on: [:update]
  after_commit :log_status_broadcast_check, on: [:update]
  after_commit :check_workflow_failure_on_node_failure, on: [:update]

  # Status check methods
  def pending?
    status == 'pending'
  end

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def cancelled?
    status == 'cancelled'
  end

  def skipped?
    status == 'skipped'
  end

  def waiting_for_approval?
    status == 'waiting_approval'
  end

  def active?
    %w[pending running waiting_approval].include?(status)
  end

  def finished?
    %w[completed failed cancelled skipped].include?(status)
  end

  def successful?
    %w[completed skipped].include?(status)
  end

  # Execution control methods
  def start_execution!
    return false unless pending?

    # CRITICAL FIX: Capture status change manually for callback (same as complete_execution!)
    old_status = status
    @pending_status_change = [old_status, 'running']

    update!(
      status: 'running',
      started_at: Time.current,
      metadata: metadata.merge('execution_started_at' => Time.current.iso8601)
    )

    # Frontend calculates elapsed time locally using started_at timestamp
    # No need for periodic duration update broadcasts
  end

  def complete_execution!(output_data_hash = {}, execution_cost = 0)
    # Check if already completed
    if status == 'completed'
      Rails.logger.warn "Node #{execution_id} (#{ai_workflow_node.name}) already completed, skipping"
      return false
    end

    return false unless running?

    # CRITICAL FIX: Use thread-local storage for re-entry protection
    # This works even if the instance gets reloaded during callbacks
    executing_key = "completing_execution_#{execution_id}"

    if Thread.current[executing_key]
      Rails.logger.warn "[NodeExecution] Preventing re-entrant call to complete_execution! for #{execution_id}"
      return false
    end

    Thread.current[executing_key] = true

    begin
      # CRITICAL FIX: Capture status change manually for callback
      old_status = status
      @pending_status_change = [old_status, 'completed']

      result = update!(
        status: 'completed',
        completed_at: Time.current,
        output_data: output_data.merge(output_data_hash),
        cost: cost + execution_cost.to_f,
        metadata: metadata.merge('execution_completed_at' => Time.current.iso8601)
      )

      result
    ensure
      # Always clear the flag, even if an exception occurs
      Thread.current[executing_key] = nil
    end
  end

  def fail_execution!(error_message, error_details_hash = {})
    # CRITICAL FIX: Use thread-local storage for re-entry protection
    failing_key = "failing_execution_#{execution_id}"

    if Thread.current[failing_key]
      Rails.logger.warn "[NodeExecution] Preventing re-entrant call to fail_execution! for #{execution_id}"
      return false
    end

    Thread.current[failing_key] = true

    begin
      # CRITICAL FIX: Capture status change manually for callback
      old_status = status
      @pending_status_change = [old_status, 'failed']

      update!(
        status: 'failed',
        completed_at: Time.current,
        error_details: error_details.merge({
          'error_message' => error_message,
          'failed_at' => Time.current.iso8601
        }.merge(error_details_hash)),
        metadata: metadata.merge('execution_failed_at' => Time.current.iso8601)
      )
    ensure
      Thread.current[failing_key] = nil
    end
  end

  def cancel_execution!(reason = 'Workflow cancelled')
    return false if finished?

    # CRITICAL FIX: Capture status change manually for callback
    old_status = status
    @pending_status_change = [old_status, 'cancelled']

    update!(
      status: 'cancelled',
      cancelled_at: Time.current,
      completed_at: Time.current,
      error_details: error_details.merge({
        'cancellation_reason' => reason,
        'cancelled_at' => Time.current.iso8601
      }),
      metadata: metadata.merge('execution_cancelled_at' => Time.current.iso8601)
    )
  end

  def skip_execution!(reason = 'Condition not met')
    return false unless pending?

    update!(
      status: 'skipped',
      completed_at: Time.current,
      metadata: metadata.merge({
        'skip_reason' => reason,
        'skipped_at' => Time.current.iso8601
      })
    )
  end

  # Public method to force broadcast status update (useful for fixing sync issues)
  def force_status_broadcast!
    Rails.logger.info "Force broadcasting status for node: #{ai_workflow_node.name} (#{status})"
    broadcast_node_status_change
  end

  def request_approval!(approval_message, approvers = [])
    return false unless running?

    update!(
      status: 'waiting_approval',
      metadata: metadata.merge({
        'approval_message' => approval_message,
        'approvers' => approvers,
        'approval_requested_at' => Time.current.iso8601
      })
    )
  end

  def approve_execution!(approved_by_user_id, decision_data = {})
    return false unless waiting_for_approval?

    if decision_data['approved'] == true
      update!(
        status: 'running',
        metadata: metadata.merge({
          'approval_decision' => 'approved',
          'approved_by' => approved_by_user_id,
          'approval_completed_at' => Time.current.iso8601,
          'approval_data' => decision_data
        })
      )
    else
      fail_execution!('Approval denied', {
        'approval_decision' => 'denied',
        'denied_by' => approved_by_user_id,
        'denial_reason' => decision_data['reason']
      })
    end
  end

  # Retry management
  def can_retry?
    failed? && retry_count < max_retries
  end

  def retry_execution!
    return false unless can_retry?

    transaction do
      increment!(:retry_count)

      update!(
        status: 'pending',
        started_at: nil,
        completed_at: nil,
        cancelled_at: nil,
        error_details: {},
        metadata: metadata.merge({
          'retry_attempt' => retry_count + 1,
          'retried_at' => Time.current.iso8601
        })
      )

      log_info('node_retry_scheduled', "Node execution retry scheduled (attempt #{retry_count}/#{max_retries})")
    end

    true
  end

  def exhaust_retries!
    update!(
      retry_count: max_retries,
      metadata: metadata.merge('retries_exhausted_at' => Time.current.iso8601)
    )
  end

  # Retry with strategy service
  def retry_with_strategy!(error_type = nil)
    retry_service = AiWorkflowRetryStrategyService.new(
      node_execution: self,
      error_type: error_type
    )

    if retry_service.retryable?
      retry_service.execute_retry
    else
      Rails.logger.warn "[NodeExecution] Cannot retry #{execution_id}: #{retry_service.retry_stats}"
      false
    end
  end

  # Get retry statistics
  def retry_statistics
    retry_service = AiWorkflowRetryStrategyService.new(node_execution: self)
    retry_service.retry_stats
  end

  # Check if error type is retryable
  def error_retryable?(error_type)
    retry_service = AiWorkflowRetryStrategyService.new(
      node_execution: self,
      error_type: error_type
    )
    retry_service.retryable?
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

  def timeout_duration
    ai_workflow_node.timeout_seconds || 300
  end

  def timed_out?
    return false unless running? && started_at
    
    Time.current - started_at > timeout_duration
  end

  def time_remaining
    return nil unless running? && started_at
    
    elapsed = Time.current - started_at
    [timeout_duration - elapsed.to_i, 0].max
  end

  # Node-specific execution methods
  def execute_node!
    return false unless pending?

    begin
      start_execution!
      
      case node_type
      when 'ai_agent'
        execute_ai_agent_node
      when 'api_call'
        execute_api_call_node
      when 'webhook'
        execute_webhook_node
      when 'condition'
        execute_condition_node
      when 'loop'
        execute_loop_node
      when 'transform'
        execute_transform_node
      when 'delay'
        execute_delay_node
      when 'human_approval'
        execute_human_approval_node
      when 'sub_workflow'
        execute_sub_workflow_node
      when 'merge'
        execute_merge_node
      when 'split'
        execute_split_node
      else
        fail_execution!("Unknown node type: #{node_type}")
      end
    rescue StandardError => e
      fail_execution!("Node execution failed: #{e.message}", {
        'exception_class' => e.class.name,
        'exception_backtrace' => e.backtrace&.first(10)
      })
    end
  end

  # Input/Output data management
  def get_input(key)
    input_data[key.to_s] || input_data[key.to_sym]
  end

  def set_output(key, value)
    self.output_data = output_data.merge(key.to_s => value)
    save!
  end

  def merge_output(new_data)
    return if new_data.blank?
    
    self.output_data = output_data.merge(new_data.stringify_keys)
    save!
  end

  def get_variable(name)
    # Check node-specific variables first, then workflow run variables
    input_data[name.to_s] || 
    input_data[name.to_sym] ||
    ai_workflow_run.get_variable(name)
  end

  # Logging methods - REMOVED DUPLICATE
  # These methods are defined below (lines 468-496) to delegate to workflow run
  # Keeping only the delegating versions to avoid conflicts

  # Node execution summary
  def execution_summary
    {
      execution_id: execution_id,
      node_id: node_id,
      node_type: node_type,
      node_name: ai_workflow_node.name,
      status: status,
      duration_seconds: execution_duration_seconds,
      cost: cost,
      retry_count: retry_count,
      max_retries: max_retries,
      timestamps: {
        created: created_at,
        started: started_at,
        completed: completed_at,
        cancelled: cancelled_at
      },
      has_error: error_details.present?,
      error_message: error_details['error_message'],
      input_keys: input_data.keys,
      output_keys: output_data.keys
    }
  end

  # Node configuration helpers
  def node_configuration(key = nil)
    config = configuration_snapshot.present? ? configuration_snapshot : ai_workflow_node.configuration
    key ? config[key.to_s] : config
  end

  def node_metadata(key = nil)
    node_meta = ai_workflow_node.metadata
    key ? node_meta[key.to_s] : node_meta
  end

  # Logging methods that delegate to workflow run but include node context
  def log_info(event_type, message, context = {})
    ai_workflow_run.log(
      'info',
      event_type,
      message,
      context.merge('node_id' => node_id, 'execution_id' => execution_id),
      self
    )
  end

  def log_error(event_type, message, context = {})
    ai_workflow_run.log(
      'error',
      event_type,
      message,
      context.merge('node_id' => node_id, 'execution_id' => execution_id),
      self
    )
  end

  def log_warning(event_type, message, context = {})
    ai_workflow_run.log(
      'warn',
      event_type,
      message,
      context.merge('node_id' => node_id, 'execution_id' => execution_id),
      self
    )
  end

  # CRITICAL: These methods are called explicitly by the orchestrator after node completion
  # They cannot be private because they're invoked from Mcp::AiWorkflowOrchestrator
  # These were intentionally converted from callbacks to explicit calls to prevent stack overflow
  def update_run_progress
    # CRITICAL FIX: Use thread-local storage for re-entry protection
    progress_key = "updating_run_progress_#{ai_workflow_run_id}"

    return if Thread.current[progress_key]

    Thread.current[progress_key] = true

    begin
      # Call the workflow run's update_progress! method
      # This method is responsible for recalculating and persisting progress
      ai_workflow_run.update_progress!
    ensure
      Thread.current[progress_key] = nil
    end
  end

  # Add cost to run - called explicitly by orchestrator after node completion
  # No longer used as a callback to avoid stack overflow
  def add_cost_to_run_explicit(cost_amount)
    return unless cost_amount.present? && cost_amount > 0

    # CRITICAL FIX: Use thread-local storage for re-entry protection
    cost_key = "adding_cost_to_run_#{ai_workflow_run_id}"

    return if Thread.current[cost_key]

    Thread.current[cost_key] = true

    begin
      # Call the workflow run's add_cost method
      # This method handles the cost increment and logging
      ai_workflow_run.add_cost(cost_amount, "node_#{node_id}")
    ensure
      Thread.current[cost_key] = nil
    end
  end

  private

  def should_broadcast_status_change?
    return false unless saved_change_to_status?

    old_status, new_status = saved_change_to_status

    # Only broadcast on meaningful status transitions
    broadcast_transitions = [
      ['running', 'completed'],
      ['running', 'failed'],
      ['running', 'cancelled'],
      ['pending', 'running'],
      ['waiting_approval', 'running']
    ]

    broadcast_transitions.include?([old_status, new_status])
  end

  def log_status_broadcast_check
    # Status broadcast logging handled by broadcast_node_status_change_if_needed
  end

  def broadcast_node_status_change
    Rails.logger.info "[NodeExecution] Broadcasting node status change: #{execution_id} -> #{status} (#{ai_workflow_node.name})"
    # Broadcast to the unified AI orchestration channel with unified event name
    begin
      if defined?(AiOrchestrationChannel)
        # Use broadcast_node_execution with default event name 'node.execution.updated'
        # CRITICAL FIX: Don't override event name - use channel's default
        AiOrchestrationChannel.broadcast_node_execution(self)
      else
        Rails.logger.warn "[NodeExecution] AiOrchestrationChannel not available, skipping WebSocket broadcast"
      end
    rescue NameError => e
      Rails.logger.error "[NodeExecution] WebSocket broadcast failed (channel not loaded): #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    rescue StandardError => e
      Rails.logger.error "[NodeExecution] WebSocket broadcast failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end

  def broadcast_node_status_change_if_needed
    # CRITICAL: Use @pending_status_change because saved_change_to_status? is cleared in after_commit
    # The @pending_status_change is set manually in the state transition methods (start_execution!, complete_execution!, etc.)

    if @pending_status_change
      old_status, new_status = @pending_status_change

      broadcast_transitions = [
        ['running', 'completed'],
        ['running', 'failed'],
        ['running', 'cancelled'],
        ['pending', 'running'],
        ['waiting_approval', 'running']
      ]

      should_broadcast = broadcast_transitions.include?([old_status, new_status])

      if should_broadcast
        broadcast_node_status_change
      end

      # Clear the pending change after broadcasting
      @pending_status_change = nil
    end
  end

  def check_workflow_failure_on_node_failure
    # Check if this node failure should trigger workflow failure
    if @pending_status_change
      old_status, new_status = @pending_status_change

      # Only trigger on transition to failed status
      if new_status == 'failed' && old_status != 'failed'
        # Node failures are handled by the MCP orchestrator's error recovery system
        # The orchestrator monitors node executions and handles failures automatically
        begin
          # Log the failure for monitoring
          ai_workflow_run.log(
            'error',
            'node_execution_failed',
            "Node #{ai_workflow_node.name} failed",
            {
              'node_id' => node_id,
              'execution_id' => execution_id,
              'error_details' => error_details
            },
            self
          )
        rescue StandardError => e
          Rails.logger.error "Failed to log node failure: #{e.message}"
        end
      end
    end
  end

  def generate_execution_id
    self.execution_id = SecureRandom.uuid if execution_id.blank?
  end

  def validate_retry_limits
    return unless retry_count.present? && max_retries.present?

    if retry_count > max_retries
      errors.add(:retry_count, 'cannot exceed max_retries')
    end
  end

  def log_node_execution_started
    log_info('node_started', "Node execution started: #{ai_workflow_node.name}", {
      'node_type' => node_type,
      'input_keys' => input_data.keys,
      'max_retries' => max_retries
    })
  end

  def log_status_changes
    old_status = saved_change_to_status[0]
    new_status = saved_change_to_status[1]
    
    # Map status changes to valid event types
    event_type = case new_status
    when 'running'
      'node_started'
    when 'completed'
      'node_completed'
    when 'failed'
      'node_failed'
    when 'cancelled'
      'node_cancelled'
    when 'skipped'
      'node_skipped'
    else
      'node_started' # fallback
    end
    
    log_info(event_type, "Node status changed from #{old_status} to #{new_status}", {
      'old_status' => old_status,
      'new_status' => new_status,
      'duration_ms' => execution_time_ms
    })
  end

  def calculate_duration
    return unless started_at && completed_at

    # Ensure positive duration - handle edge cases where completed_at < started_at
    duration_seconds = completed_at - started_at
    calculated_duration_ms = [duration_seconds * 1000, 0].max.to_i

    # Use update_column to avoid triggering callbacks (prevents stack overflow)
    if duration_ms != calculated_duration_ms
      update_column(:duration_ms, calculated_duration_ms)
    end
  end

  # Legacy method - kept for backward compatibility but no longer used as callback
  def add_cost_to_run
    return unless saved_change_to_cost&.last.present?

    cost_added = saved_change_to_cost.last - (saved_change_to_cost.first || 0)
    return unless cost_added > 0

    add_cost_to_run_explicit(cost_added)
  end

  # Node-specific execution methods (simplified versions - will be expanded by services)
  def execute_ai_agent_node
    agent_id = node_configuration('agent_id')
    
    if agent_id.blank?
      fail_execution!('No agent specified for AI agent node')
      return
    end

    agent = account.ai_agents.find_by(id: agent_id)
    if agent.nil?
      fail_execution!("AI agent not found: #{agent_id}")
      return
    end

    # This will be delegated to a specialized service
    log_info('ai_agent_execution_queued', 'AI agent execution queued', {
      'agent_id' => agent_id,
      'agent_name' => agent.name
    })

    # For now, mark as running - actual execution will be handled by worker jobs
    # The AiWorkflowNodeExecutorService will handle the detailed execution
  end

  def execute_api_call_node
    url = node_configuration('url')
    method = node_configuration('method') || 'GET'
    
    if url.blank?
      fail_execution!('No URL specified for API call node')
      return
    end

    log_info('api_call_queued', "API call queued: #{method} #{url}")
    # Actual execution will be handled by worker jobs
  end

  def execute_webhook_node
    url = node_configuration('url')
    
    if url.blank?
      fail_execution!('No URL specified for webhook node')
      return
    end

    log_info('webhook_queued', "Webhook queued: #{url}")
    # Actual execution will be handled by worker jobs
  end

  def execute_condition_node
    conditions = node_configuration('conditions')
    
    if conditions.blank?
      fail_execution!('No conditions specified for condition node')
      return
    end

    log_info('condition_evaluation_queued', 'Condition evaluation queued')
    # Actual execution will be handled by worker jobs
  end

  def execute_loop_node
    iteration_source = node_configuration('iteration_source')
    
    if iteration_source.blank?
      fail_execution!('No iteration source specified for loop node')
      return
    end

    log_info('loop_execution_queued', 'Loop execution queued')
    # Actual execution will be handled by worker jobs
  end

  def execute_transform_node
    transformations = node_configuration('transformations')
    
    if transformations.blank?
      fail_execution!('No transformations specified for transform node')
      return
    end

    log_info('transform_execution_queued', 'Transform execution queued')
    # Actual execution will be handled by worker jobs
  end

  def execute_delay_node
    delay_seconds = node_configuration('delay_seconds')
    
    if delay_seconds.blank? || delay_seconds.to_i <= 0
      fail_execution!('Invalid delay specified for delay node')
      return
    end

    log_info('delay_scheduled', "Delay scheduled for #{delay_seconds} seconds")
    # Actual execution will be handled by worker jobs
  end

  def execute_human_approval_node
    approval_message = node_configuration('approval_message')
    approvers = node_configuration('approvers') || []
    
    if approvers.empty?
      fail_execution!('No approvers specified for human approval node')
      return
    end

    request_approval!(approval_message, approvers)
    log_info('approval_requested', 'Human approval requested', {
      'approvers' => approvers,
      'message' => approval_message
    })
  end

  def execute_sub_workflow_node
    workflow_id = node_configuration('workflow_id')
    
    if workflow_id.blank?
      fail_execution!('No sub-workflow specified')
      return
    end

    sub_workflow = account.ai_workflows.find_by(id: workflow_id)
    if sub_workflow.nil?
      fail_execution!("Sub-workflow not found: #{workflow_id}")
      return
    end

    log_info('sub_workflow_queued', "Sub-workflow execution queued: #{sub_workflow.name}")
    # Actual execution will be handled by worker jobs
  end

  def execute_merge_node
    merge_strategy = node_configuration('merge_strategy') || 'wait_all'
    
    log_info('merge_execution_queued', "Merge execution queued with strategy: #{merge_strategy}")
    # Actual execution will be handled by worker jobs
  end

  def execute_split_node
    split_strategy = node_configuration('split_strategy') || 'parallel'
    branches = node_configuration('branches') || []
    
    log_info('split_execution_queued', "Split execution queued with strategy: #{split_strategy}")
    # Actual execution will be handled by worker jobs
  end
end