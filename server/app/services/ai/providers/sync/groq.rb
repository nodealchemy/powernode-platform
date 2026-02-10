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
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            if credential
              begin
                api_key = credential.credentials["api_key"]
                response = HTTP.headers(
                  "Authorization" => "Bearer #{api_key}",
                  "Content-Type" => "application/json"
                ).timeout(15).get("https://api.groq.com/openai/v1/models")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["data"] || []

                  supported_models = models.map do |model|
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

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from Groq API for provider #{provider.id}"
                  return true
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching Groq models: #{e.message}, falling back to static models"
              end
            end

            handle_sync_failure(provider, "Failed to sync Groq models: no valid credentials or API error")
          end

          def format_groq_model_name(model_id)
            model_id.split("-").map(&:capitalize).join(" ").gsub(/(\d)b/i, '\1B')
          end
        end
      end
    end
  end
end
