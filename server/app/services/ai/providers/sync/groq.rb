# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Groq
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_groq_models(provider)
            # Groq uses OpenAI-compatible API
            sync_bearer_models(provider, url: "https://api.groq.com/openai/v1/models", label: "Groq") do |models|
              models.map do |model|
                {
                  "name" => format_groq_model_name(model["id"]),
                  "id" => model["id"],
                  "context_length" => model["context_window"] || 8192,
                  "max_output_tokens" => 8192,
                  "description" => model["id"],
                  "capabilities" => %w[text_generation chat],
                  "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                  "owned_by" => model["owned_by"],
                  "context_window" => model["context_window"]
                }
              end
            end
          end

          def format_groq_model_name(model_id)
            model_id.split("-").map(&:capitalize).join(" ").gsub(/(\d)b/i, '\1B')
          end
        end
      end
    end
  end
end
