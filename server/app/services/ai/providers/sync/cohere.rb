# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Cohere
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_cohere_models(provider)
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            if credential
              begin
                api_key = credential.credentials["api_key"]
                response = HTTP.headers(
                  "Authorization" => "Bearer #{api_key}",
                  "Content-Type" => "application/json"
                ).timeout(15).get("https://api.cohere.com/v1/models")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["models"] || []

                  supported_models = models.map do |model|
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

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from Cohere API for provider #{provider.id}"
                  return true
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching Cohere models: #{e.message}, falling back to static models"
              end
            end

            handle_sync_failure(provider, "Failed to sync Cohere models: no valid credentials or API error")
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
