# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Grok
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_grok_models(provider)
            # X.AI uses OpenAI-compatible API
            sync_bearer_models(provider, url: "https://api.x.ai/v1/models", label: "Grok", success_label: "X.AI") do |models|
              models.map do |model|
                {
                  "name" => format_grok_model_name(model["id"]),
                  "id" => model["id"],
                  "context_length" => 131072,
                  "max_output_tokens" => 8192,
                  "description" => model["id"],
                  "capabilities" => grok_capabilities(model["id"]),
                  "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                  "owned_by" => model["owned_by"]
                }
              end
            end
          end

          def format_grok_model_name(model_id)
            model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
          end

          def grok_capabilities(model_id)
            caps = %w[text_generation chat function_calling]
            caps << "vision" if model_id.include?("vision")
            caps
          end
        end
      end
    end
  end
end
