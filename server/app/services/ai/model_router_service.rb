# frozen_string_literal: true

module Ai
  class ModelRouterService
    include ActiveModel::Model
    include ProviderScoring
    include RoutingAnalytics
    include TaskClassification

    class NoProvidersAvailableError < StandardError; end
    class RoutingError < StandardError; end

    # Available routing strategies
    STRATEGIES = %w[
      cost_optimized
      latency_optimized
      quality_optimized
      round_robin
      weighted
      hybrid
      ml_based
    ].freeze

    # Default weights for hybrid strategy
    DEFAULT_WEIGHTS = {
      cost: 0.4,
      latency: 0.3,
      quality: 0.2,
      reliability: 0.1
    }.freeze

    # Model tier definitions for automatic routing
    MODEL_TIERS = {
      "economy" => %w[gpt-4.1-nano haiku claude-3-5-haiku claude-haiku-4-5].freeze,
      "standard" => %w[gpt-4.1-mini o4-mini claude-sonnet claude-sonnet-4 claude-sonnet-4-5].freeze,
      "premium" => %w[gpt-4.1 o3 claude-opus claude-opus-4 claude-opus-4-5 claude-opus-4-6].freeze
    }.freeze

    # Task type -> default model tier mapping
    TASK_TIER_MAP = {
      "classification" => "economy",
      "extraction" => "economy",
      "formatting" => "economy",
      "routing" => "economy",
      "simple_qa" => "economy",
      "summarization" => "standard",
      "translation" => "standard",
      "analysis" => "standard",
      "code_review" => "standard",
      "agent_task" => "standard",
      "reasoning" => "premium",
      "code_generation" => "premium",
      "creative" => "premium",
      "critical_decision" => "premium"
    }.freeze

    def initialize(account:, strategy: "cost_optimized", custom_weights: nil)
      @account = account
      @strategy = strategy
      @custom_weights = custom_weights || DEFAULT_WEIGHTS
      @logger = Rails.logger
      @redis = Powernode::Redis.client

      raise ArgumentError, "Invalid strategy: #{strategy}" unless STRATEGIES.include?(strategy)
    end

    # Route a request to the optimal provider
    def route(request_context)
      start_time = Time.current

      # Find matching routing rules
      matching_rules = find_matching_rules(request_context)

      # Get available providers
      available_providers = get_available_providers(request_context)

      raise NoProvidersAvailableError, "No providers available for request" if available_providers.empty?

      # Score and select provider
      selected_provider, scoring_details = select_optimal_provider(
        providers: available_providers,
        request_context: request_context,
        matching_rules: matching_rules
      )

      # Record the routing decision
      decision = record_routing_decision(
        provider: selected_provider,
        request_context: request_context,
        matching_rule: matching_rules.first,
        scoring_details: scoring_details,
        start_time: start_time
      )

      {
        provider: selected_provider,
        decision_id: decision.id,
        strategy_used: @strategy,
        scoring: scoring_details,
        estimated_cost: scoring_details[:estimated_cost_usd],
        estimated_latency_ms: scoring_details[:estimated_latency_ms]
      }
    end

    # Route and execute a request with automatic fallback
    def route_and_execute(request_context, max_retries: 3)
      attempted_providers = []
      last_error = nil
      decision = nil

      max_retries.times do |attempt|
        begin
          # Get routing decision, excluding already attempted providers
          routing = route(request_context.merge(exclude_providers: attempted_providers))
          provider = routing[:provider]
          decision = Ai::RoutingDecision.find(routing[:decision_id])

          attempted_providers << provider.id

          # Execute the request
          execution_start = Time.current
          result = yield(provider)
          execution_time = ((Time.current - execution_start) * 1000).to_i

          # Record successful outcome
          decision.record_outcome!(
            outcome: "succeeded",
            cost_usd: result[:cost_usd],
            latency_ms: execution_time,
            tokens_used: result[:tokens_used],
            quality_score: result[:quality_score]
          )

          # Record provider metrics
          record_provider_metrics(provider, result.merge(latency_ms: execution_time, success: true))

          return {
            result: result,
            provider: provider,
            decision: decision,
            attempts: attempt + 1
          }

        rescue StandardError => e
          last_error = e
          @logger.error "Routing attempt #{attempt + 1} failed: #{e.message}"

          # Record failure
          decision&.record_outcome!(outcome: "failed")

          # Record provider metrics
          if provider
            record_provider_metrics(provider, { success: false, error: e.message })
          end

          next if attempt < max_retries - 1
        end
      end

      raise RoutingError, "All routing attempts failed. Last error: #{last_error&.message}"
    end
  end
end
