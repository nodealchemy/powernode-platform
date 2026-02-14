# frozen_string_literal: true

class Ai::ProviderLoadBalancerService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class NoProvidersAvailableError < StandardError; end
  class LoadBalancingError < StandardError; end

  LOAD_BALANCING_STRATEGIES = %w[round_robin weighted_round_robin least_connections cost_optimized performance_based].freeze

  def initialize(account, capability: "text_generation", strategy: "cost_optimized")
    @account = account
    @capability = capability
    @strategy = strategy
    @logger = Rails.logger
    @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")

    raise ArgumentError, "Invalid strategy: #{strategy}" unless LOAD_BALANCING_STRATEGIES.include?(strategy)
  end

  # Select the best provider for the request
  def select_provider(request_metadata = {})
    available_providers = get_available_providers
    raise NoProvidersAvailableError, "No providers available for capability: #{@capability}" if available_providers.empty?

    selected_provider = case @strategy
    when "round_robin"
      select_round_robin(available_providers)
    when "weighted_round_robin"
      select_weighted_round_robin(available_providers)
    when "least_connections"
      select_least_connections(available_providers)
    when "cost_optimized"
      select_cost_optimized(available_providers, request_metadata)
    when "performance_based"
      select_performance_based(available_providers)
    else
      available_providers.sample # Fallback to random selection
    end

    # Update provider metrics
    increment_provider_usage(selected_provider)

    @logger.info "Selected provider #{selected_provider.name} using #{@strategy} strategy"
    selected_provider
  end

  # Execute a request with automatic fallback
  def execute_with_fallback(request_type, **options, &block)
    max_retries = options.delete(:max_provider_retries) || 3
    attempted_providers = []

    max_retries.times do |attempt|
      begin
        provider = select_provider(options)
        next if attempted_providers.include?(provider.id)

        attempted_providers << provider.id

        # Create client and execute request
        credential = provider.provider_credentials.active.first
        raise LoadBalancingError, "No active credentials for provider #{provider.name}" unless credential

        client = Ai::ProviderClientService.new(credential)
        result = yield(client, provider)

        # Record successful execution
        record_execution_success(provider, options)
        return result

      rescue Ai::ProviderCircuitBreakerService::CircuitBreakerOpenError => e
        @logger.warn "Provider #{provider.name} circuit breaker open, trying next provider (attempt #{attempt + 1})"
        record_execution_failure(provider, e, "circuit_breaker_open")
        next
      rescue StandardError => e
        @logger.error "Provider #{provider.name} failed: #{e.message} (attempt #{attempt + 1})"
        record_execution_failure(provider, e, "execution_error")

        # If it's the last attempt, re-raise the error
        raise if attempt == max_retries - 1
        next
      end
    end

    raise NoProvidersAvailableError, "All providers failed or unavailable after #{max_retries} attempts"
  end

  # Get current load balancing statistics
  def load_balancing_stats
    available_providers = get_available_providers

    {
      strategy: @strategy,
      capability: @capability,
      available_providers: available_providers.size,
      providers: available_providers.map do |provider|
        circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
        {
          id: provider.id,
          name: provider.name,
          current_load: get_provider_current_load(provider),
          circuit_state: circuit_breaker.circuit_state,
          avg_response_time: get_provider_avg_response_time(provider),
          success_rate: get_provider_success_rate(provider),
          cost_per_1k_tokens: estimate_provider_cost(provider),
          last_used: get_provider_last_used(provider)
        }
      end
    }
  end

  # Reset load balancing state (useful for testing)
  def reset_load_balancing_state
    available_providers = get_available_providers
    available_providers.each do |provider|
      @redis.del(
        provider_usage_key(provider),
        provider_response_times_key(provider),
        provider_success_key(provider),
        provider_failure_key(provider)
      )
    end
    @redis.del(round_robin_counter_key)
    @logger.info "Reset load balancing state for #{available_providers.size} providers"
  end

  private

  def get_available_providers
    @account.ai_providers
            .joins(:provider_credentials)
            .where(ai_provider_credentials: { is_active: true })
            .where(
              "(capabilities->>?) IS NOT NULL AND (capabilities->>?) != 'false'",
              @capability,
              @capability
            )
            .distinct
            .to_a
            .select do |provider|
              circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
              circuit_breaker.provider_available?
            end
  end

  def select_round_robin(providers)
    counter = @redis.incr(round_robin_counter_key)
    @redis.expire(round_robin_counter_key, 1.hour) # Reset every hour
    providers[counter % providers.size]
  end

  def select_weighted_round_robin(providers)
    # Weight based on provider performance and cost
    weighted_providers = providers.flat_map do |provider|
      weight = calculate_provider_weight(provider)
      [ provider ] * weight.clamp(1, 10) # Ensure at least 1, max 10
    end

    select_round_robin(weighted_providers)
  end

  def select_least_connections(providers)
    providers.min_by { |provider| get_provider_current_load(provider) }
  end

  def select_cost_optimized(providers, request_metadata)
    estimated_tokens = estimate_token_usage(request_metadata)

    providers.min_by do |provider|
      cost_score = estimate_provider_cost(provider) * estimated_tokens
      load_penalty = get_provider_current_load(provider) * 0.1
      response_time_penalty = get_provider_avg_response_time(provider) * 0.01

      cost_score + load_penalty + response_time_penalty
    end
  end

  def select_performance_based(providers)
    providers.min_by do |provider|
      response_time = get_provider_avg_response_time(provider)
      success_rate = get_provider_success_rate(provider)
      current_load = get_provider_current_load(provider)

      # Lower is better: prioritize speed and success rate, penalize high load
      score = response_time * 0.5 + (100 - success_rate) * 0.3 + current_load * 0.2
      score
    end
  end

  def calculate_provider_weight(provider)
    success_rate = get_provider_success_rate(provider)
    avg_response_time = get_provider_avg_response_time(provider)
    current_load = get_provider_current_load(provider)

    # Higher success rate and lower response time = higher weight
    weight = (success_rate / 10.0) - (avg_response_time / 1000.0) - (current_load / 10.0)
    weight.clamp(1, 10).round
  end

  def estimate_token_usage(request_metadata)
    # Simple token estimation based on prompt length
    prompt_length = request_metadata.dig(:prompt)&.length || 100
    (prompt_length / 4.0).ceil # Rough approximation: 1 token ≈ 4 characters
  end

  def estimate_provider_cost(provider)
    # Get cost from provider configuration or use defaults
    provider.configuration.dig("pricing", @capability, "per_1k_tokens") || 0.002
  end

  def get_provider_current_load(provider)
    (@redis.get(provider_usage_key(provider)) || 0).to_i
  end

  def get_provider_avg_response_time(provider)
    response_times_json = @redis.get(provider_response_times_key(provider))
    return 1000.0 unless response_times_json # Default to 1 second if no data

    response_times = JSON.parse(response_times_json)
    return 1000.0 if response_times.empty?

    response_times.sum.to_f / response_times.size
  end

  def get_provider_success_rate(provider)
    successes = (@redis.get(provider_success_key(provider)) || 0).to_i
    failures = (@redis.get(provider_failure_key(provider)) || 0).to_i
    total = successes + failures

    return 100.0 if total == 0 # No data means 100% success rate
    (successes.to_f / total * 100).round(2)
  end

  def get_provider_last_used(provider)
    timestamp = @redis.get(provider_last_used_key(provider))
    timestamp ? Time.parse(timestamp) : nil
  end

  def increment_provider_usage(provider)
    @redis.incr(provider_usage_key(provider))
    @redis.expire(provider_usage_key(provider), 5.minutes) # Usage decays over 5 minutes
    @redis.set(provider_last_used_key(provider), Time.current.iso8601)
  end

  def record_execution_success(provider, options)
    @redis.incr(provider_success_key(provider))
    @redis.expire(provider_success_key(provider), 1.hour)

    # Record response time if provided
    if options[:execution_time_ms]
      record_response_time(provider, options[:execution_time_ms])
    end
  end

  def record_execution_failure(provider, error, failure_type)
    @redis.incr(provider_failure_key(provider))
    @redis.expire(provider_failure_key(provider), 1.hour)

    # Log failure details
    @logger.error "Provider #{provider.name} failed (#{failure_type}): #{error.message}"
  end

  def record_response_time(provider, response_time_ms)
    key = provider_response_times_key(provider)
    response_times_json = @redis.get(key) || "[]"
    response_times = JSON.parse(response_times_json)

    # Keep only last 100 response times
    response_times << response_time_ms
    response_times = response_times.last(100)

    @redis.set(key, response_times.to_json)
    @redis.expire(key, 1.hour)
  end

  # Redis keys
  def round_robin_counter_key
    "load_balancer:#{@account.id}:#{@capability}:round_robin_counter"
  end

  def provider_usage_key(provider)
    "load_balancer:#{@account.id}:provider:#{provider.id}:usage"
  end

  def provider_response_times_key(provider)
    "load_balancer:#{@account.id}:provider:#{provider.id}:response_times"
  end

  def provider_success_key(provider)
    "load_balancer:#{@account.id}:provider:#{provider.id}:successes"
  end

  def provider_failure_key(provider)
    "load_balancer:#{@account.id}:provider:#{provider.id}:failures"
  end

  def provider_last_used_key(provider)
    "load_balancer:#{@account.id}:provider:#{provider.id}:last_used"
  end
end
