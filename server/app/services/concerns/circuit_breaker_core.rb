# frozen_string_literal: true

# CircuitBreakerCore - Shared circuit breaker logic
#
# Provides core circuit breaker functionality for any service that needs
# protection against cascading failures. Implements the classic pattern:
# closed → open (after failures) → half_open (after timeout) → closed (after success)
#
# Usage:
#   class MyCircuitBreaker
#     include CircuitBreakerCore
#
#     def initialize(resource_id)
#       setup_circuit_breaker(
#         resource_id: resource_id,
#         config: {
#           failure_threshold: 5,
#           success_threshold: 2,
#           timeout_duration: 60_000,
#           monitoring_window: 300_000
#         }
#       )
#     end
#   end
#
module CircuitBreakerCore
  extend ActiveSupport::Concern

  # Circuit breaker states
  STATES = %w[closed open half_open].freeze

  # Default configuration
  DEFAULT_CONFIG = {
    failure_threshold: 5,        # Failures before opening
    success_threshold: 2,        # Successes to close from half-open
    timeout_duration: 60_000,    # Time before trying half-open (ms)
    monitoring_window: 300_000,  # 5 minutes rolling window
    reset_timeout: 300_000       # Time to reset after successful close
  }.freeze

  class CircuitOpenError < StandardError; end

  included do
    attr_reader :service_name, :resource_id, :config, :state_key
  end

  # Setup circuit breaker - call from initializer
  #
  # @param resource_id [String] Unique identifier for the protected resource
  # @param service_name [String] Human-readable service name (optional)
  # @param config [Hash] Configuration overrides. Supports :storage option (:cache or :redis)
  def setup_circuit_breaker(resource_id:, service_name: nil, config: {})
    config = config.symbolize_keys
    @storage_backend = config.delete(:storage) || :cache
    if @storage_backend == :redis
      @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
    end

    @resource_id = resource_id
    @service_name = service_name || resource_id
    @config = DEFAULT_CONFIG.merge(config)
    @state_key = build_state_key(resource_id)
    load_circuit_state
  end

  # Execute a block with circuit breaker protection
  #
  # @yield Block to execute
  # @return Result of the block
  # @raise [CircuitOpenError] if circuit is open and timeout hasn't elapsed
  def execute_with_circuit_breaker(&block)
    check_circuit_state_transition

    case @state
    when "open"
      handle_open_circuit
    when "half_open"
      execute_half_open(&block)
    else # closed
      execute_closed(&block)
    end
  end

  # Check if circuit breaker allows execution
  #
  # @return [Boolean] true if requests are allowed
  def allow_request?
    check_circuit_state_transition

    case @state
    when "open"
      false
    when "half_open", "closed"
      true
    else
      false
    end
  end

  # Get current circuit breaker state
  #
  # @return [String] Current state ('closed', 'open', or 'half_open')
  def circuit_state
    check_circuit_state_transition
    @state
  end

  # Get circuit breaker statistics
  #
  # @return [Hash] Statistics including state, counts, and timestamps
  def circuit_stats
    {
      service_name: @service_name,
      resource_id: @resource_id,
      state: @state,
      failure_count: @failure_count,
      success_count: @success_count,
      consecutive_failures: @consecutive_failures,
      consecutive_successes: @consecutive_successes,
      last_failure_time: @last_failure_time,
      last_success_time: @last_success_time,
      state_changed_at: @state_changed_at,
      next_retry_at: calculate_next_retry_time,
      config: @config
    }
  end

  # Reset circuit breaker to closed state
  #
  # @return [void]
  def reset_circuit!
    @state = "closed"
    @failure_count = 0
    @success_count = 0
    @consecutive_failures = 0
    @consecutive_successes = 0
    @last_failure_time = nil
    @last_success_time = nil
    @state_changed_at = Time.current
    save_circuit_state

    log_info "Circuit breaker reset"
  end

  # Force open the circuit (for maintenance)
  #
  # @return [void]
  def force_open!
    transition_state("open")
    log_warn "Circuit breaker manually opened"
  end

  # Force close the circuit (after manual verification)
  #
  # @return [void]
  def force_close!
    transition_state("closed")
    @failure_count = 0
    @consecutive_failures = 0
    save_circuit_state
    log_info "Circuit breaker manually closed"
  end

  private

  # Build the cache key for circuit state
  # Override this in including class for custom key format
  #
  # @param resource_id [String] Resource identifier
  # @return [String] Cache key
  def build_state_key(resource_id)
    "circuit_breaker:#{resource_id}"
  end

  # Load circuit state from storage
  # Dispatches to cache or Redis based on @storage_backend
  #
  # @return [void]
  def load_circuit_state
    @storage_backend == :redis ? redis_load_state : cache_load_state
  end

  # Save circuit state to storage
  # Dispatches to cache or Redis based on @storage_backend
  #
  # @return [void]
  def save_circuit_state
    @storage_backend == :redis ? redis_save_state : cache_save_state
  end

  def cache_load_state
    cached = Rails.cache.read(@state_key)

    if cached
      @state = cached[:state] || "closed"
      @failure_count = cached[:failure_count] || 0
      @success_count = cached[:success_count] || 0
      @consecutive_failures = cached[:consecutive_failures] || 0
      @consecutive_successes = cached[:consecutive_successes] || 0
      @last_failure_time = cached[:last_failure_time]
      @last_success_time = cached[:last_success_time]
      @state_changed_at = cached[:state_changed_at] || Time.current
    else
      reset_circuit!
    end
  end

  def cache_save_state
    Rails.cache.write(@state_key, {
      state: @state,
      failure_count: @failure_count,
      success_count: @success_count,
      consecutive_failures: @consecutive_failures,
      consecutive_successes: @consecutive_successes,
      last_failure_time: @last_failure_time,
      last_success_time: @last_success_time,
      state_changed_at: @state_changed_at
    }, expires_in: 24.hours)
  end

  def redis_load_state
    state_data = @redis.get(@state_key)

    if state_data
      cached = JSON.parse(state_data, symbolize_names: true)
      @state = cached[:state] || "closed"
      @failure_count = cached[:failure_count] || 0
      @success_count = cached[:success_count] || 0
      @consecutive_failures = cached[:consecutive_failures] || 0
      @consecutive_successes = cached[:consecutive_successes] || 0
      @last_failure_time = cached[:last_failure_time] ? Time.parse(cached[:last_failure_time]) : nil
      @last_success_time = cached[:last_success_time] ? Time.parse(cached[:last_success_time]) : nil
      @state_changed_at = cached[:state_changed_at] ? Time.parse(cached[:state_changed_at]) : Time.current
    else
      reset_circuit!
    end
  rescue JSON::ParserError, StandardError => e
    Rails.logger.error "[CircuitBreaker:#{@service_name}] Failed to load Redis state: #{e.message}"
    reset_circuit!
  end

  def redis_save_state
    state_data = {
      state: @state,
      failure_count: @failure_count,
      success_count: @success_count,
      consecutive_failures: @consecutive_failures,
      consecutive_successes: @consecutive_successes,
      last_failure_time: @last_failure_time&.iso8601,
      last_success_time: @last_success_time&.iso8601,
      state_changed_at: @state_changed_at.iso8601
    }

    @redis.set(@state_key, state_data.to_json)
    @redis.expire(@state_key, 24.hours.to_i)
  rescue StandardError => e
    Rails.logger.error "[CircuitBreaker:#{@service_name}] Failed to save Redis state: #{e.message}"
  end

  # Check if circuit should transition from open to half-open
  #
  # @return [void]
  def check_circuit_state_transition
    return unless @state == "open"

    # Check if timeout has elapsed for half-open transition
    if timeout_elapsed?
      transition_state("half_open")
      log_info "Circuit transitioned to half-open state"
    end
  end

  # Execute block in closed state
  #
  # @yield Block to execute
  # @return Result of the block
  def execute_closed(&block)
    result = block.call
    record_success
    result
  rescue StandardError => e
    record_failure(e)
    raise
  end

  # Execute block in half-open state
  #
  # @yield Block to execute
  # @return Result of the block
  def execute_half_open(&block)
    result = block.call
    record_success

    # If we've had enough successes, close the circuit
    if @consecutive_successes >= @config[:success_threshold]
      transition_state("closed")
      log_info "Circuit closed after successful recovery"
    end

    result
  rescue StandardError => e
    record_failure(e)
    transition_state("open")
    log_warn "Circuit reopened after failure in half-open state"
    raise
  end

  # Handle open circuit state
  #
  # @raise [CircuitOpenError] Always raises
  def handle_open_circuit
    error_msg = "Circuit breaker is open for #{@service_name}. " \
                "Service is unavailable. Next retry at #{calculate_next_retry_time}"

    log_warn error_msg
    raise CircuitOpenError, error_msg
  end

  # Record a successful execution
  #
  # @return [void]
  def record_success
    @success_count += 1
    @consecutive_successes += 1
    @consecutive_failures = 0
    @last_success_time = Time.current
    save_circuit_state

    log_debug "Success recorded (consecutive: #{@consecutive_successes})"
  end

  # Record a failed execution
  #
  # @param error [StandardError] The error that occurred
  # @return [void]
  def record_failure(error)
    @failure_count += 1
    @consecutive_failures += 1
    @consecutive_successes = 0
    @last_failure_time = Time.current
    save_circuit_state

    log_warn "Failure recorded: #{error.message} " \
             "(consecutive: #{@consecutive_failures}/#{@config[:failure_threshold]})"

    # Check if we should open the circuit
    if @consecutive_failures >= @config[:failure_threshold]
      transition_state("open")
      log_error "Circuit opened after #{@consecutive_failures} consecutive failures"
    end
  end

  # Transition to a new state
  #
  # @param new_state [String] The new state to transition to
  # @return [void]
  def transition_state(new_state)
    old_state = @state
    @state = new_state
    @state_changed_at = Time.current

    if new_state == "closed"
      @failure_count = 0
      @consecutive_failures = 0
      @consecutive_successes = 0
    elsif new_state == "half_open"
      @consecutive_successes = 0
    end

    save_circuit_state

    # Hook for state change notification
    on_state_change(old_state, new_state) if respond_to?(:on_state_change, true)
  end

  # Check if timeout has elapsed for half-open transition
  #
  # @return [Boolean] true if timeout has elapsed
  def timeout_elapsed?
    return false unless @last_failure_time

    elapsed_ms = ((Time.current - @last_failure_time) * 1000).to_i
    elapsed_ms >= @config[:timeout_duration]
  end

  # Calculate when the circuit can be retried
  #
  # @return [Time, nil] Time when circuit can be retried, or nil if not open
  def calculate_next_retry_time
    return nil unless @state == "open" && @last_failure_time

    @last_failure_time + (@config[:timeout_duration] / 1000.0).seconds
  end

  # Logging helpers
  def log_debug(message)
    Rails.logger.debug "[CircuitBreaker:#{@service_name}] #{message}"
  end

  def log_info(message)
    Rails.logger.info "[CircuitBreaker:#{@service_name}] #{message}"
  end

  def log_warn(message)
    Rails.logger.warn "[CircuitBreaker:#{@service_name}] #{message}"
  end

  def log_error(message)
    Rails.logger.error "[CircuitBreaker:#{@service_name}] #{message}"
  end
end
