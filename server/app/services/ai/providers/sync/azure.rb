# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Azure
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_azure_models(provider)
            # Azure OpenAI models - these depend on user's deployed models
            # Using common deployment names as defaults
            current_models = [
              {
                "name" => "GPT-4o",
                "id" => "gpt-4o",
                "context_length" => 128000,
                "max_output_tokens" => 16384,
                "description" => "Most advanced multimodal model on Azure",
                "capabilities" => %w[text_generation chat vision function_calling],
                "cost_per_1k_tokens" => model_pricing_for("gpt-4o")
              },
              {
                "name" => "GPT-4o Mini",
                "id" => "gpt-4o-mini",
                "context_length" => 128000,
                "max_output_tokens" => 16384,
                "description" => "Affordable and intelligent small model on Azure",
                "capabilities" => %w[text_generation chat vision function_calling],
                "cost_per_1k_tokens" => model_pricing_for("gpt-4o-mini")
              },
              {
                "name" => "GPT-4 Turbo",
                "id" => "gpt-4-turbo",
                "context_length" => 128000,
                "max_output_tokens" => 4096,
                "description" => "GPT-4 Turbo with Vision on Azure",
                "capabilities" => %w[text_generation chat vision function_calling],
                "cost_per_1k_tokens" => model_pricing_for("gpt-4-turbo")
              }
            ]

            provider.update(supported_models: current_models)
            Rails.logger.info "Successfully synced #{current_models.length} models for Azure provider #{provider.id}"
            true
          end
        end
      end
    end
  end
end
