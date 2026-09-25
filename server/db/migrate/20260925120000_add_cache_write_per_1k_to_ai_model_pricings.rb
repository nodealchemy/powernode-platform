# frozen_string_literal: true

# Anthropic bills prompt-cache WRITES above the base input rate; the catalog
# modelled only reads (cached_input_per_1k). PricingSyncService fills this from
# LiteLLM's cache_creation_input_token_cost; 0 means "not modelled", and
# Ai::CostCalculationService then prices writes at the input rate.
class AddCacheWritePer1kToAiModelPricings < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_model_pricings, :cache_write_per_1k, :decimal, precision: 12, scale: 8, default: "0.0"
  end
end
