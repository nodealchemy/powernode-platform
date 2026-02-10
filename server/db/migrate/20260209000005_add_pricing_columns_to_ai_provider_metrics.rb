# frozen_string_literal: true

class AddPricingColumnsToAiProviderMetrics < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_provider_metrics, :model_tier, :string
    add_column :ai_provider_metrics, :cached_input_cost_per_1k, :decimal, precision: 12, scale: 8
    add_column :ai_provider_metrics, :cache_write_cost_per_1k, :decimal, precision: 12, scale: 8
  end
end
