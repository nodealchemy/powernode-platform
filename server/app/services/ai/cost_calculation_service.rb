# frozen_string_literal: true

module Ai
  class CostCalculationService
    # Calculate cost in USD from token counts and model pricing.
    #
    # Uses PricingSyncService.pricing_for as the canonical 3-tier lookup:
    #   1. DB exact match (ai_model_pricings)
    #   2. DB prefix match
    #   3. MODEL_PRICING constant fallback (40+ models)
    #
    # Cache reads (cached_tokens) and cache writes (cache_creation_tokens) are
    # SUBSETS of prompt_tokens (the Ai::Llm::Response usage invariant). Reads
    # are charged at the catalog's cached_input rate and writes at its
    # cache_write rate; a rate the catalog does not model (0) falls back to the
    # input rate. The uncached remainder is charged at the input rate.
    #
    # @param model_id [String] e.g. "claude-sonnet-4-6", "gpt-4o"
    # @param prompt_tokens [Integer] total input tokens (cache reads and writes included)
    # @param completion_tokens [Integer] output tokens
    # @param cached_tokens [Integer] cache reads (subset of prompt_tokens)
    # @param cache_creation_tokens [Integer] cache writes (subset of prompt_tokens)
    # @return [Float] cost in USD
    def self.calculate(model_id:, prompt_tokens: 0, completion_tokens: 0, cached_tokens: 0, cache_creation_tokens: 0)
      pricing = Ai::Autonomy::PricingSyncService.pricing_for(model_id.to_s)
      return 0.0 unless pricing

      input_per_1k = pricing["input"].to_f
      read_per_1k = pricing["cached_input"].to_f.positive? ? pricing["cached_input"].to_f : input_per_1k
      write_per_1k = pricing["cache_write"].to_f.positive? ? pricing["cache_write"].to_f : input_per_1k
      uncached = [ prompt_tokens - cached_tokens - cache_creation_tokens, 0 ].max

      input_cost = (uncached / 1000.0) * input_per_1k +
                   (cached_tokens / 1000.0) * read_per_1k +
                   (cache_creation_tokens / 1000.0) * write_per_1k
      output_cost = (completion_tokens / 1000.0) * pricing["output"].to_f

      (input_cost + output_cost).round(6)
    end

    # Convenience: calculate and return cost in cents (Integer, ceiled, min 0)
    def self.calculate_cents(...)
      cost_usd = calculate(...)
      return 0 if cost_usd <= 0

      (cost_usd * 100).ceil
    end
  end
end
