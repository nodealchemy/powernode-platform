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
    # Cached tokens are a subset of prompt_tokens charged at a discounted rate
    # (typically 75-90% cheaper) instead of the full input rate.
    #
    # @param model_id [String] e.g. "claude-sonnet-4-6", "gpt-4o"
    # @param prompt_tokens [Integer] total input tokens (including cached)
    # @param completion_tokens [Integer] output tokens
    # @param cached_tokens [Integer] cached input tokens (subset of prompt_tokens)
    # @return [Float] cost in USD
    def self.calculate(model_id:, prompt_tokens: 0, completion_tokens: 0, cached_tokens: 0)
      pricing = Ai::Autonomy::PricingSyncService.pricing_for(model_id.to_s)
      return 0.0 unless pricing

      input_per_1k = pricing["input"].to_f
      output_per_1k = pricing["output"].to_f
      cached_per_1k = pricing["cached_input"].to_f

      # Cached tokens are a subset of prompt_tokens — charge them at the
      # discounted rate instead of the full input rate.
      non_cached_input = [prompt_tokens - cached_tokens, 0].max

      input_cost = if cached_per_1k > 0 && cached_tokens > 0
                     (non_cached_input / 1000.0) * input_per_1k +
                       (cached_tokens / 1000.0) * cached_per_1k
                   else
                     (prompt_tokens / 1000.0) * input_per_1k
                   end

      output_cost = (completion_tokens / 1000.0) * output_per_1k

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
