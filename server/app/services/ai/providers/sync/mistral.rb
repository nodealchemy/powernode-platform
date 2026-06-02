# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Mistral
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_mistral_models(provider)
            sync_bearer_models(provider, url: "https://api.mistral.ai/v1/models", label: "Mistral") do |models|
              models.map do |model|
                {
                  "name" => format_mistral_model_name(model["id"]),
                  "id" => model["id"],
                  "context_length" => model["max_context_length"] || 32000,
                  "max_output_tokens" => 8192,
                  "description" => model["description"] || model["id"],
                  "capabilities" => mistral_capabilities(model["id"]),
                  "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                  "owned_by" => model["owned_by"]
                }
              end
            end
          end

          def format_mistral_model_name(model_id)
            model_id.gsub("-latest", "").gsub("-", " ").split.map(&:capitalize).join(" ")
          end

          def mistral_capabilities(model_id)
            caps = %w[text_generation chat]
            caps << "function_calling" if model_id.include?("large") || model_id.include?("small")
            caps << "vision" if model_id.include?("pixtral")
            caps << "code_generation" if model_id.include?("codestral")
            caps
          end
        end
      end
    end
  end
end
