# frozen_string_literal: true

module Ai
  module Routing
    # Service for managing prefix caching configuration across AI providers.
    #
    # Prefix caching allows providers to reuse previously computed KV cache
    # for identical message prefixes, reducing both latency and cost.
    #
    # Provider-specific behavior:
    # - Anthropic: Explicit cache_control breakpoints (max 4 per request)
    # - OpenAI: Automatic for prompts >1024 tokens (no config needed)
    # - Ollama: keep_alive parameter to retain model in memory
    #
    # Usage:
    #   service = Ai::Routing::PrefixCacheService.new(account: account)
    #   key = service.cache_key_for(messages: messages, model: "claude-sonnet-4")
    #   config = service.cache_config_for(provider_type: "anthropic", messages: messages)
    #
    class PrefixCacheService
      include Ai::Concerns::AccountScoped

      # Minimum token count for OpenAI automatic caching
      OPENAI_MIN_CACHE_TOKENS = 1024

      # Maximum cache control breakpoints for Anthropic
      ANTHROPIC_MAX_BREAKPOINTS = 4

      # Default keep_alive duration for Ollama (in minutes)
      OLLAMA_DEFAULT_KEEP_ALIVE = 15

      # Providers that support explicit cache control
      CACHEABLE_PROVIDERS = %w[anthropic openai ollama].freeze

      # Generate a cache key based on message prefix and model.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @return [String] Cache key hash
      def cache_key_for(messages:, model:)
        # Build a deterministic representation of the prefix
        prefix_content = messages.map do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]
          "#{role}:#{content}"
        end.join("|")

        Digest::SHA256.hexdigest("#{model}:#{prefix_content}")
      end

      # Determine whether caching should be enabled for this request.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @return [Boolean] Whether caching is recommended
      def should_cache?(messages:, model:)
        total_tokens = estimate_total_tokens(messages)
        provider_type = detect_provider_type(model)

        case provider_type
        when "anthropic"
          # Anthropic benefits from caching when there's a system prompt
          has_system = messages.any? { |m| (m[:role] || m["role"]) == "system" }
          has_system || total_tokens > 500
        when "openai"
          # OpenAI automatic caching kicks in at 1024+ tokens
          total_tokens >= OPENAI_MIN_CACHE_TOKENS
        when "ollama"
          # Ollama benefits from keep_alive for repeated requests
          true
        else
          total_tokens >= OPENAI_MIN_CACHE_TOKENS
        end
      end

      # Generate provider-specific cache configuration.
      #
      # @param provider_type [String] Provider type (anthropic, openai, ollama)
      # @param messages [Array<Hash>] Conversation messages
      # @return [Hash] Provider-specific cache configuration
      def cache_config_for(provider_type:, messages:)
        case provider_type.to_s.downcase
        when "anthropic"
          anthropic_cache_config(messages)
        when "openai"
          openai_cache_config(messages)
        when "ollama"
          ollama_cache_config
        else
          { caching_enabled: false, reason: "unsupported_provider" }
        end
      end

      # Estimate potential savings from prefix caching.
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param provider_type [String] Provider type
      # @return [Hash] Savings estimate
      def estimate_cache_savings(messages:, provider_type:)
        total_tokens = estimate_total_tokens(messages)
        cacheable_tokens = estimate_cacheable_tokens(messages)

        case provider_type.to_s.downcase
        when "anthropic"
          # Anthropic: cached reads are 90% cheaper than fresh reads
          savings_ratio = 0.9
          {
            total_tokens: total_tokens,
            cacheable_tokens: cacheable_tokens,
            potential_savings_ratio: savings_ratio,
            estimated_savings_per_request: (cacheable_tokens * savings_ratio * 0.000003).round(6),
            cache_write_overhead: (cacheable_tokens * 0.25 * 0.000003).round(6)
          }
        when "openai"
          # OpenAI: cached prompts are 50% cheaper
          savings_ratio = 0.5
          {
            total_tokens: total_tokens,
            cacheable_tokens: total_tokens >= OPENAI_MIN_CACHE_TOKENS ? cacheable_tokens : 0,
            potential_savings_ratio: savings_ratio,
            estimated_savings_per_request: (cacheable_tokens * savings_ratio * 0.00001).round(6),
            cache_write_overhead: 0
          }
        else
          {
            total_tokens: total_tokens,
            cacheable_tokens: 0,
            potential_savings_ratio: 0,
            estimated_savings_per_request: 0,
            cache_write_overhead: 0
          }
        end
      end

      private

      def anthropic_cache_config(messages)
        breakpoints = []
        system_messages = messages.select { |m| (m[:role] || m["role"]) == "system" }

        # Add cache control to system messages (most valuable for caching)
        system_messages.each_with_index do |msg, idx|
          break if breakpoints.length >= ANTHROPIC_MAX_BREAKPOINTS

          breakpoints << {
            message_index: messages.index(msg),
            type: "system",
            cache_control: { type: "ephemeral" }
          }
        end

        # If we have room, add breakpoints at conversation turn boundaries
        if breakpoints.length < ANTHROPIC_MAX_BREAKPOINTS
          # Find the last user message before the current turn
          user_indices = messages.each_with_index
                                 .select { |m, _| (m[:role] || m["role"]) == "user" }
                                 .map(&:last)

          if user_indices.length > 1
            # Cache up to the second-to-last user message
            cache_point = user_indices[-2]
            breakpoints << {
              message_index: cache_point,
              type: "conversation_prefix",
              cache_control: { type: "ephemeral" }
            }
          end
        end

        {
          caching_enabled: breakpoints.any?,
          provider: "anthropic",
          breakpoints: breakpoints,
          max_breakpoints: ANTHROPIC_MAX_BREAKPOINTS
        }
      end

      def openai_cache_config(messages)
        total_tokens = estimate_total_tokens(messages)

        {
          caching_enabled: total_tokens >= OPENAI_MIN_CACHE_TOKENS,
          provider: "openai",
          automatic: true,
          min_tokens: OPENAI_MIN_CACHE_TOKENS,
          current_tokens: total_tokens,
          note: "OpenAI automatically caches prompts >= #{OPENAI_MIN_CACHE_TOKENS} tokens"
        }
      end

      def ollama_cache_config
        {
          caching_enabled: true,
          provider: "ollama",
          keep_alive: "#{OLLAMA_DEFAULT_KEEP_ALIVE}m",
          note: "Model kept in memory for #{OLLAMA_DEFAULT_KEEP_ALIVE} minutes between requests"
        }
      end

      def detect_provider_type(model)
        model_lower = model.to_s.downcase
        if model_lower.include?("claude") || model_lower.include?("haiku") || model_lower.include?("sonnet") || model_lower.include?("opus")
          "anthropic"
        elsif model_lower.include?("gpt") || model_lower.include?("o3") || model_lower.include?("o4")
          "openai"
        elsif model_lower.include?("llama") || model_lower.include?("mistral") || model_lower.include?("gemma")
          "ollama"
        else
          "unknown"
        end
      end

      def estimate_total_tokens(messages)
        messages.sum { |m| estimate_message_tokens(m) }
      end

      def estimate_message_tokens(message)
        content = message[:content] || message["content"] || ""
        (content.length / 4.0).ceil + 4
      end

      def estimate_cacheable_tokens(messages)
        # System messages and all but the last user message are cacheable
        cacheable = messages.select do |m|
          role = m[:role] || m["role"]
          role == "system"
        end

        # Also include earlier conversation turns (all but last message)
        if messages.length > 1
          cacheable += messages[0...-1].reject { |m| (m[:role] || m["role"]) == "system" }
        end

        cacheable.sum { |m| estimate_message_tokens(m) }
      end
    end
  end
end
