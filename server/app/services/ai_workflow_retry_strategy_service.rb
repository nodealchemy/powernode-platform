# frozen_string_literal: true

class AiWorkflowRetryStrategyService
  attr_reader :node_execution, :retry_config, :error_type

  # Retry strategies
  STRATEGIES = {
    exponential: "ExponentialBackoff",
    linear: "LinearBackoff",
    fixed: "FixedBackoff",
    custom: "CustomBackoff"
  }.freeze

  # Default configuration
  DEFAULT_CONFIG = {
    max_retries: 3,
    initial_delay_ms: 1000,
    max_delay_ms: 60_000,
    backoff_multiplier: 2,
    jitter: true,
    retry_on_errors: %w[timeout rate_limit temporary_failure network_error]
  }.freeze

  def initialize(node_execution:, error_type: nil)
    @node_execution = node_execution
    @error_type = error_type
    @retry_config = build_retry_config
  end

  # Check if the error is retryable
  def retryable?
    return false unless retry_enabled?
    return false if max_retries_reached?
    return false unless error_is_retryable?

    true
  end

  # Calculate next retry delay in milliseconds
  def calculate_retry_delay
    strategy_class = get_strategy_class
    strategy = strategy_class.new(
      attempt: current_retry_attempt,
      config: retry_config
    )

    delay_ms = strategy.calculate_delay

    # Add jitter if enabled
    if retry_config[:jitter]
      jitter_amount = (delay_ms * 0.1).to_i # 10% jitter
      delay_ms += rand(-jitter_amount..jitter_amount)
    end

    # Ensure within bounds
    [ delay_ms, retry_config[:max_delay_ms] ].min
  end

  # Execute retry with appropriate delay
  def execute_retry
    unless retryable?
      Rails.logger.warn "[Retry] Cannot retry node execution #{node_execution.id}: not retryable"
      return false
    end

    delay_ms = calculate_retry_delay

    Rails.logger.info "[Retry] Scheduling retry for node execution #{node_execution.id} " \
                      "in #{delay_ms}ms (attempt #{current_retry_attempt + 1}/#{retry_config[:max_retries]})"

    # Update retry metadata
    update_retry_metadata(delay_ms)

    # Broadcast retry scheduled event
    broadcast_retry_event(delay_ms)

    # Schedule retry using worker
    WorkerJobService.enqueue_node_execution_retry(
      node_execution.id,
      delay_ms: delay_ms
    )

    true
  end

  # Broadcast retry event via WebSocket
  def broadcast_retry_event(delay_ms)
    workflow_run = node_execution.workflow_run

    ActionCable.server.broadcast(
      "ai_workflow_run_#{workflow_run.id}",
      {
        type: "node_retry_scheduled",
        node_execution_id: node_execution.id,
        node_id: node_execution.node_id,
        attempt: current_retry_attempt + 1,
        max_retries: retry_config[:max_retries],
        delay_ms: delay_ms,
        error_type: error_type,
        timestamp: Time.current.iso8601
      }
    )
  rescue StandardError => e
    Rails.logger.warn "[Retry] Failed to broadcast retry event: #{e.message}"
  end

  # Get retry statistics
  def retry_stats
    {
      current_attempt: current_retry_attempt,
      max_retries: retry_config[:max_retries],
      retries_remaining: retry_config[:max_retries] - current_retry_attempt,
      total_retry_time_ms: total_retry_time,
      last_retry_at: last_retry_timestamp,
      next_retry_delay_ms: retryable? ? calculate_retry_delay : nil,
      error_type: error_type,
      retryable: retryable?
    }
  end

  private

  def retry_enabled?
    retry_config[:enabled] == true
  end

  def max_retries_reached?
    current_retry_attempt >= retry_config[:max_retries]
  end

  def error_is_retryable?
    return true if error_type.nil? # Default to retryable if no error type specified

    retry_on_errors = retry_config[:retry_on_errors] || []
    retry_on_errors.include?(error_type.to_s)
  end

  def current_retry_attempt
    node_execution.metadata.dig("retry", "attempt_count").to_i
  end

  def total_retry_time
    node_execution.metadata.dig("retry", "total_delay_ms").to_i
  end

  def last_retry_timestamp
    node_execution.metadata.dig("retry", "last_retry_at")
  end

  def build_retry_config
    # Get node-level configuration
    node_config = node_execution.node&.configuration || {}
    node_retry_config = node_config["retry"] || {}

    # Get workflow-level configuration
    workflow = node_execution.workflow_run&.workflow
    workflow_config = workflow&.configuration || {}
    workflow_retry_config = workflow_config["retry"] || {}

    # Merge configurations (node overrides workflow overrides default)
    DEFAULT_CONFIG
      .merge(workflow_retry_config.symbolize_keys)
      .merge(node_retry_config.symbolize_keys)
  end

  def get_strategy_class
    strategy_name = retry_config[:strategy] || :exponential
    strategy_class_name = STRATEGIES[strategy_name.to_sym] || STRATEGIES[:exponential]

    "AiWorkflowRetryStrategyService::#{strategy_class_name}".constantize
  end

  def update_retry_metadata(delay_ms)
    current_metadata = node_execution.metadata || {}
    retry_metadata = current_metadata["retry"] || {}

    updated_retry_metadata = retry_metadata.merge(
      "attempt_count" => current_retry_attempt + 1,
      "last_retry_at" => Time.current.iso8601,
      "last_delay_ms" => delay_ms,
      "total_delay_ms" => total_retry_time + delay_ms,
      "error_type" => error_type,
      "retry_scheduled_at" => Time.current.iso8601
    )

    node_execution.update(
      metadata: current_metadata.merge("retry" => updated_retry_metadata)
    )
  end

  # ============================================================================
  # Retry Strategy Implementations
  # ============================================================================

  # Base strategy class
  class BaseStrategy
    attr_reader :attempt, :config

    def initialize(attempt:, config:)
      @attempt = attempt
      @config = config
    end

    def calculate_delay
      raise NotImplementedError, "Subclass must implement calculate_delay"
    end
  end

  # Exponential backoff: delay = initial * (multiplier ^ attempt)
  class ExponentialBackoff < BaseStrategy
    def calculate_delay
      initial_delay = config[:initial_delay_ms] || 1000
      multiplier = config[:backoff_multiplier] || 2

      delay = initial_delay * (multiplier ** attempt)
      [ delay, config[:max_delay_ms] || 60_000 ].min
    end
  end

  # Linear backoff: delay = initial + (increment * attempt)
  class LinearBackoff < BaseStrategy
    def calculate_delay
      initial_delay = config[:initial_delay_ms] || 1000
      increment = config[:linear_increment_ms] || 1000

      delay = initial_delay + (increment * attempt)
      [ delay, config[:max_delay_ms] || 60_000 ].min
    end
  end

  # Fixed backoff: delay = constant
  class FixedBackoff < BaseStrategy
    def calculate_delay
      config[:fixed_delay_ms] || config[:initial_delay_ms] || 1000
    end
  end

  # Custom backoff: use custom delay array
  class CustomBackoff < BaseStrategy
    def calculate_delay
      delay_schedule = config[:custom_delays_ms] || [ 1000, 2000, 5000 ]
      delay_schedule[attempt] || delay_schedule.last || 5000
    end
  end
end
