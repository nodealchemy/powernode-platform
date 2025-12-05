# frozen_string_literal: true

# Circuit Breaker pattern implementation for API resilience
# Prevents cascading failures by temporarily stopping requests to failing services
module CircuitBreaker
  extend ActiveSupport::Concern

  class CircuitBreakerError < StandardError; end
  class CircuitOpenError < CircuitBreakerError; end

  included do
    attr_reader :circuit_breaker_state
  end

  # Circuit breaker states
  CLOSED = :closed     # Normal operation
  OPEN = :open         # Failing, reject requests
  HALF_OPEN = :half_open # Testing if service recovered

  module ClassMethods
    def with_circuit_breaker(service_name, options = {})
      circuit_breaker = CircuitBreakerService.new(service_name, options)

      yield circuit_breaker
    end
  end

  class CircuitBreakerService
    attr_reader :service_name, :state, :failure_count, :last_failure_time, :options

    DEFAULT_OPTIONS = {
      failure_threshold: 5,
      recovery_timeout: 60,  # seconds
      timeout: 30,           # request timeout in seconds
      retry_timeout: 10      # seconds to wait before retry in half-open state
    }.freeze

    def initialize(service_name, options = {})
      @service_name = service_name
      @options = DEFAULT_OPTIONS.merge(options)
      @state = CLOSED
      @failure_count = 0
      @last_failure_time = nil
      @last_success_time = nil
      @mutex = Mutex.new
      @logger = PowernodeWorker.application.logger
    end

    def call
      # Check state and determine action WITHOUT holding mutex during execution
      action = @mutex.synchronize do
        case @state
        when CLOSED
          :execute
        when OPEN
          if ready_for_half_open?
            transition_to_half_open
            :execute
          else
            :raise_circuit_open
          end
        when HALF_OPEN
          :execute
        end
      end

      # Execute the determined action without holding the mutex
      case action
      when :execute
        execute_request { yield }
      when :raise_circuit_open
        raise CircuitOpenError, "Circuit breaker is OPEN for #{@service_name}. Last failure: #{@last_failure_time}"
      end
    end

    def healthy?
      @state == CLOSED
    end

    def failing?
      @state == OPEN
    end

    def testing?
      @state == HALF_OPEN
    end

    def status
      {
        service: @service_name,
        state: @state,
        failure_count: @failure_count,
        last_failure_time: @last_failure_time,
        last_success_time: @last_success_time,
        next_retry_time: next_retry_time,
        options: @options
      }
    end

    private

    def execute_request
      start_time = Time.current

      begin
        # Set request timeout
        result = Timeout.timeout(@options[:timeout]) do
          yield
        end

        # Success: reset failure count and ensure circuit is closed
        on_success
        result

      rescue Timeout::Error => e
        @logger.error "[CircuitBreaker] Timeout for #{@service_name}: #{e.message}"
        on_failure(e)
        raise
      rescue StandardError => e
        @logger.error "[CircuitBreaker] Request failed for #{@service_name}: #{e.message}"
        on_failure(e)
        raise
      ensure
        duration = Time.current - start_time
        @logger.debug "[CircuitBreaker] #{@service_name} request completed in #{duration.round(3)}s"
      end
    end

    def on_success
      @mutex.synchronize do
        @failure_count = 0
        @last_success_time = Time.current

        if @state == HALF_OPEN
          transition_to_closed
          @logger.info "[CircuitBreaker] #{@service_name} circuit breaker transitioned to CLOSED"
        end
      end
    end

    def on_failure(exception)
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.current

        @logger.warn "[CircuitBreaker] #{@service_name} failure ##{@failure_count}: #{exception.message}"

        if @state == CLOSED && @failure_count >= @options[:failure_threshold]
          transition_to_open
          @logger.error "[CircuitBreaker] #{@service_name} circuit breaker OPENED after #{@failure_count} failures"
        elsif @state == HALF_OPEN
          transition_to_open
          @logger.error "[CircuitBreaker] #{@service_name} circuit breaker returned to OPEN state"
        end
      end
    end

    def ready_for_half_open?
      return false unless @last_failure_time

      Time.current - @last_failure_time >= @options[:recovery_timeout]
    end

    def next_retry_time
      return nil unless @last_failure_time

      @last_failure_time + @options[:recovery_timeout]
    end

    def transition_to_closed
      @state = CLOSED
    end

    def transition_to_open
      @state = OPEN
    end

    def transition_to_half_open
      @state = HALF_OPEN
      @logger.info "[CircuitBreaker] #{@service_name} circuit breaker transitioned to HALF_OPEN for testing"
    end
  end

  # Global circuit breaker registry
  class CircuitBreakerRegistry
    include Singleton

    def initialize
      @breakers = {}
      @mutex = Mutex.new
    end

    def get_breaker(service_name, options = {})
      @mutex.synchronize do
        @breakers[service_name] ||= CircuitBreakerService.new(service_name, options)
      end
    end

    def all_breakers
      @mutex.synchronize do
        @breakers.dup
      end
    end

    def reset_breaker(service_name)
      @mutex.synchronize do
        @breakers.delete(service_name)
      end
    end

    def status
      all_breakers.transform_values(&:status)
    end
  end

  # Helper methods for common circuit breaker patterns
  def with_backend_api_circuit_breaker(&block)
    breaker = CircuitBreakerRegistry.instance.get_breaker(
      'backend_api',
      failure_threshold: 5,
      recovery_timeout: 60,
      timeout: 120
    )

    breaker.call(&block)
  end

  # Separate circuit breaker for web interface authentication
  # More tolerant of failures to prevent web auth issues from affecting worker jobs
  def with_web_auth_circuit_breaker(&block)
    breaker = CircuitBreakerRegistry.instance.get_breaker(
      'web_auth_api',
      failure_threshold: 10,  # Higher threshold - web auth failures shouldn't block workers
      recovery_timeout: 60,   # Longer recovery time for web interface
      timeout: 15
    )

    breaker.call(&block)
  end

  def with_ai_provider_circuit_breaker(provider_name, &block)
    breaker = CircuitBreakerRegistry.instance.get_breaker(
      "ai_provider_#{provider_name}",
      failure_threshold: 5,      # Allow more failures before opening (was 2)
      recovery_timeout: 120,     # Longer recovery time for AI services (was 60)
      timeout: 600              # 10 minutes to accommodate long AI operations (was 30)
    )

    breaker.call(&block)
  end

  # Dedicated circuit breaker for AI workflow execution
  # Higher timeout to accommodate complex workflows with multiple AI agent calls
  def with_workflow_execution_circuit_breaker(&block)
    breaker = CircuitBreakerRegistry.instance.get_breaker(
      'workflow_execution',
      failure_threshold: 3,
      recovery_timeout: 30,
      timeout: 300  # 5 minutes for complex workflows
    )

    breaker.call(&block)
  end

  def circuit_breaker_status
    CircuitBreakerRegistry.instance.status
  end

  def reset_circuit_breaker(service_name)
    CircuitBreakerRegistry.instance.reset_breaker(service_name)
  end
end