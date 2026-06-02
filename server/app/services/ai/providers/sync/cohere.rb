# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Cohere
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_cohere_models(provider)
            sync_bearer_models(provider, url: "https://api.cohere.com/v1/models", label: "Cohere", models_key: "models") do |models|
              models.map do |model|
                model_id = model["id"] || model["name"]
                {
                  "name" => model["name"] || format_cohere_model_name(model_id),
                  "id" => model_id,
                  "context_length" => model["context_length"] || 4096,
                  "max_output_tokens" => model["max_output_tokens"] || 4096,
                  "description" => model["description"] || model["name"],
                  "capabilities" => cohere_capabilities(model_id),
                  "cost_per_1k_tokens" => model_pricing_for(model_id),
                  "endpoints" => model["endpoints"]
                }
              end
            end
          end

          def format_cohere_model_name(model_id)
            return model_id unless model_id.is_a?(String)
            model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
          end

          def cohere_capabilities(model_id)
            return %w[embeddings] if model_id.to_s.include?("embed")
            return %w[rerank] if model_id.to_s.include?("rerank")
            %w[text_generation chat function_calling]
          end
        end
      end
    end
  end
end
