# frozen_string_literal: true

# AiErrorRecoveryService - Intelligent error recovery for AI provider operations
#
# This service implements sophisticated error recovery strategies for AI provider
# interactions, including retry logic, provider fallback, and circuit breaker patterns.
#
# Key responsibilities:
# - Error classification and categorization
# - Retry logic with configurable backoff strategies
# - Provider fallback and switching
# - Circuit breaker pattern implementation
# - Recovery statistics and monitoring
#
# Architecture:
# - Strategy pattern for different error types
# - Exponential/linear backoff for retries
# - Provider health tracking via Redis
# - Circuit breaker state management
# - Recovery attempt logging and metrics
#
# Error Types & Strategies:
# - rate_limit: Exponential backoff retry (5 attempts)
# - timeout: Linear backoff retry (3 attempts)
# - authentication: Switch to alternative provider
# - quota_exceeded: Switch to alternative provider
# - model_unavailable: Switch model or provider
# - network_error: Exponential backoff retry (4 attempts)
# - server_error: Exponential backoff retry (3 attempts)
# - validation_error: Modify request parameters
# - circuit_breaker: Switch to healthy provider
#
# @example Execute with automatic recovery
#   recovery = AiErrorRecoveryService.new(account, execution_context)
#   result = recovery.execute_with_recovery(provider, :generate_text) do
#     provider_client.generate_text(prompt, options)
#   end
#
# @example Check provider health
#   recovery.is_provider_healthy?(provider)
#
class AiErrorRecoveryService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Error classification types
  ERROR_TYPES = {
    rate_limit: { retry: true, backoff: :exponential, max_retries: 5 },
    timeout: { retry: true, backoff: :linear, max_retries: 3 },
    authentication: { retry: false, fallback: :switch_provider },
    quota_exceeded: { retry: false, fallback: :switch_provider },
    model_unavailable: { retry: true, backoff: :exponential, max_retries: 2, fallback: :switch_model },
    network_error: { retry: true, backoff: :exponential, max_retries: 4 },
    server_error: { retry: true, backoff: :exponential, max_retries: 3 },
    validation_error: { retry: false, fallback: :modify_request },
    circuit_breaker: { retry: false, fallback: :switch_provider }
  }.freeze

  class RecoveryFailedError < StandardError; end

  def initialize(account, execution_context = {})
    @account = account
    @execution_context = execution_context
    @logger = Rails.logger
    @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
    @max_recovery_attempts = 10
    @recovery_stats = {}
  end

  # Execute with comprehensive error recovery
  def execute_with_recovery(provider, request_type, **options, &block)
    attempt_count = 0
    recovery_attempts = []
    original_provider = provider
    current_provider = provider

    loop do
      attempt_count += 1
      break if attempt_count > @max_recovery_attempts

      begin
        result = execute_request(current_provider, request_type, options, &block)

        # Record successful recovery if we had previous failures
        if recovery_attempts.any?
          record_successful_recovery(original_provider, recovery_attempts)
        end

        return result

      rescue StandardError => e
        error_type = classify_error(e)
        recovery_strategy = ERROR_TYPES[error_type]

        recovery_attempts << {
          attempt: attempt_count,
          error: e.message,
          error_type: error_type,
          provider: current_provider.id,
          timestamp: Time.current
        }

        @logger.warn "AI execution failed (attempt #{attempt_count}): #{e.message}"

        # Apply recovery strategy
        if should_retry?(error_type, attempt_count)
          sleep_duration = calculate_backoff(recovery_strategy[:backoff], attempt_count)
          @logger.info "Retrying after #{sleep_duration}s (#{recovery_strategy[:backoff]} backoff)"
          sleep(sleep_duration)
          next
        elsif should_fallback?(recovery_strategy)
          current_provider = apply_fallback_strategy(
            recovery_strategy[:fallback],
            current_provider,
            error_type,
            options
          )
          next if current_provider
        end

        # If all recovery attempts failed
        record_recovery_failure(original_provider, recovery_attempts)
        raise RecoveryFailedError, "All recovery attempts failed. Last error: #{e.message}"
      end
    end

    raise RecoveryFailedError, "Maximum recovery attempts (#{@max_recovery_attempts}) exceeded"
  end

  # Get recovery statistics for monitoring
  def get_recovery_stats(time_range = 1.hour)
    stats_key = "ai_recovery:#{@account.id}:stats"
    recovery_data = @redis.hgetall(stats_key)

    {
      total_executions: recovery_data["total_executions"]&.to_i || 0,
      failed_executions: recovery_data["failed_executions"]&.to_i || 0,
      recovered_executions: recovery_data["recovered_executions"]&.to_i || 0,
      recovery_rate: calculate_recovery_rate(recovery_data),
      common_errors: get_common_error_types(time_range),
      provider_reliability: get_provider_reliability_stats(time_range),
      avg_recovery_time: recovery_data["avg_recovery_time"]&.to_f || 0.0
    }
  end

  # Reset recovery statistics
  def reset_recovery_stats
    stats_key = "ai_recovery:#{@account.id}:stats"
    error_types_key = "ai_recovery:#{@account.id}:error_types"
    provider_stats_key = "ai_recovery:#{@account.id}:provider_stats"

    @redis.del(stats_key, error_types_key, provider_stats_key)
    @logger.info "Reset recovery statistics for account #{@account.id}"
  end

  private

  def execute_request(provider, request_type, options, &block)
    # Check circuit breaker
    circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
    raise StandardError, "Circuit breaker open" unless circuit_breaker.provider_available?

    start_time = Time.current

    # Execute the actual request
    result = circuit_breaker.call do
      yield(provider, options)
    end

    execution_time = (Time.current - start_time) * 1000
    record_successful_execution(provider, execution_time)

    result
  end

  def classify_error(error)
    message = error.message.downcase

    case message
    when /rate limit|too many requests|429/
      :rate_limit
    when /timeout|timed out/
      :timeout
    when /unauthorized|authentication|401/
      :authentication
    when /quota|billing|payment/
      :quota_exceeded
    when /model.*not.*available|model.*unavailable/
      :model_unavailable
    when /network|connection|dns/
      :network_error
    when /server error|500|502|503|504/
      :server_error
    when /validation|invalid|bad request|400/
      :validation_error
    when /circuit.*breaker.*open/
      :circuit_breaker
    else
      :server_error # Default classification
    end
  end

  def should_retry?(error_type, attempt_count)
    strategy = ERROR_TYPES[error_type]
    return false unless strategy[:retry]

    attempt_count <= (strategy[:max_retries] || 3)
  end

  def should_fallback?(strategy)
    strategy && strategy[:fallback]
  end

  def calculate_backoff(backoff_type, attempt_count)
    case backoff_type
    when :exponential
      [ 2 ** attempt_count, 60 ].min # Max 60 seconds
    when :linear
      [ attempt_count * 2, 30 ].min # Max 30 seconds
    when :fixed
      5 # Fixed 5 seconds
    else
      2 # Default 2 seconds
    end
  end

  def apply_fallback_strategy(fallback_type, current_provider, error_type, options)
    case fallback_type
    when :switch_provider
      switch_to_alternative_provider(current_provider, options)
    when :switch_model
      switch_to_alternative_model(current_provider, options)
    when :modify_request
      modify_request_parameters(options, error_type)
      current_provider
    else
      nil
    end
  end

  def switch_to_alternative_provider(current_provider, options)
    load_balancer = AiProviderLoadBalancerService.new(@account)

    begin
      # Get available providers excluding the current one
      available_providers = load_balancer.send(:get_available_providers)
                                        .reject { |p| p.id == current_provider.id }

      return nil if available_providers.empty?

      # Select best alternative using load balancer logic
      alternative = available_providers.min_by do |provider|
        circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
        next Float::INFINITY unless circuit_breaker.provider_available?

        load_balancer.send(:get_provider_avg_response_time, provider)
      end

      @logger.info "Switching from #{current_provider.name} to #{alternative.name}"
      alternative

    rescue StandardError => e
      @logger.error "Failed to switch provider: #{e.message}"
      nil
    end
  end

  def switch_to_alternative_model(current_provider, options)
    current_model = options[:model] || "default"
    available_models = get_alternative_models(current_provider, current_model)

    return current_provider if available_models.empty?

    # Select a simpler/more reliable model
    alternative_model = available_models.first
    options[:model] = alternative_model

    @logger.info "Switching model from #{current_model} to #{alternative_model}"
    current_provider
  end

  def modify_request_parameters(options, error_type)
    case error_type
    when :validation_error
      # Reduce token limits if validation fails
      options[:max_tokens] = [ options[:max_tokens]&.to_i || 1000, 100 ].min
      options[:temperature] = [ options[:temperature]&.to_f || 0.7, 0.1 ].max
    when :rate_limit
      # Add jitter to reduce concurrent requests
      options[:request_delay] = rand(1..5)
    end
  end

  def get_alternative_models(provider, current_model)
    # This would be provider-specific model mapping
    case provider.slug
    when "openai"
      [ "gpt-3.5-turbo", "gpt-4" ].reject { |m| m == current_model }
    when "anthropic"
      [ "claude-3-sonnet-20240229", "claude-3-haiku-20240307" ].reject { |m| m == current_model }
    else
      []
    end
  end

  def record_successful_execution(provider, execution_time)
    stats_key = "ai_recovery:#{@account.id}:stats"

    @redis.hincrby(stats_key, "total_executions", 1)
    @redis.expire(stats_key, 24.hours)

    # Update average execution time
    current_avg = @redis.hget(stats_key, "avg_execution_time")&.to_f || 0.0
    current_count = @redis.hget(stats_key, "total_executions")&.to_i || 1

    new_avg = ((current_avg * (current_count - 1)) + execution_time) / current_count
    @redis.hset(stats_key, "avg_execution_time", new_avg.round(2))
  end

  def record_successful_recovery(original_provider, recovery_attempts)
    stats_key = "ai_recovery:#{@account.id}:stats"

    @redis.hincrby(stats_key, "recovered_executions", 1)
    @redis.expire(stats_key, 24.hours)

    recovery_time = recovery_attempts.last[:timestamp] - recovery_attempts.first[:timestamp]

    current_avg_recovery = @redis.hget(stats_key, "avg_recovery_time")&.to_f || 0.0
    recovery_count = @redis.hget(stats_key, "recovered_executions")&.to_i || 1

    new_avg_recovery = ((current_avg_recovery * (recovery_count - 1)) + recovery_time) / recovery_count
    @redis.hset(stats_key, "avg_recovery_time", new_avg_recovery.round(2))

    @logger.info "Successful recovery for #{original_provider.name} after #{recovery_attempts.size} attempts"
  end

  def record_recovery_failure(original_provider, recovery_attempts)
    stats_key = "ai_recovery:#{@account.id}:stats"
    error_types_key = "ai_recovery:#{@account.id}:error_types"

    @redis.hincrby(stats_key, "failed_executions", 1)
    @redis.expire(stats_key, 24.hours)

    # Track error types
    recovery_attempts.each do |attempt|
      @redis.hincrby(error_types_key, attempt[:error_type].to_s, 1)
    end
    @redis.expire(error_types_key, 24.hours)

    @logger.error "Recovery failed for #{original_provider.name} after #{recovery_attempts.size} attempts"
  end

  def calculate_recovery_rate(recovery_data)
    total = recovery_data["total_executions"]&.to_i || 0
    recovered = recovery_data["recovered_executions"]&.to_i || 0

    return 0.0 if total == 0
    (recovered.to_f / total * 100).round(2)
  end

  def get_common_error_types(time_range)
    error_types_key = "ai_recovery:#{@account.id}:error_types"
    error_counts = @redis.hgetall(error_types_key)

    error_counts.map do |type, count|
      { type: type, count: count.to_i }
    end.sort_by { |e| -e[:count] }.first(10)
  end

  def get_provider_reliability_stats(time_range)
    # This would aggregate provider-specific failure rates
    providers = @account.ai_providers.active

    providers.map do |provider|
      circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
      load_balancer = AiProviderLoadBalancerService.new(@account)

      {
        id: provider.id,
        name: provider.name,
        circuit_state: circuit_breaker.circuit_state,
        success_rate: load_balancer.send(:get_provider_success_rate, provider),
        avg_response_time: load_balancer.send(:get_provider_avg_response_time, provider)
      }
    end
  end
end
