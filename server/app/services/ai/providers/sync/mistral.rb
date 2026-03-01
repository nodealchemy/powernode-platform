# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Mistral
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_mistral_models(provider)
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            if credential
              begin
                api_key = credential.credentials["api_key"]
                response = HTTP.headers(
                  "Authorization" => "Bearer #{api_key}",
                  "Content-Type" => "application/json"
                ).timeout(15).get("https://api.mistral.ai/v1/models")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["data"] || []

                  supported_models = models.map do |model|
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

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from Mistral API for provider #{provider.id}"
                  return true
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching Mistral models: #{e.message}, falling back to static models"
              end
            end

            handle_sync_failure(provider, "Failed to sync Mistral models: no valid credentials or API error")
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
