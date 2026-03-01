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
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            if credential
              begin
                api_key = credential.credentials["api_key"]
                response = HTTP.headers(
                  "Authorization" => "Bearer #{api_key}",
                  "Content-Type" => "application/json"
                ).timeout(15).get("https://api.x.ai/v1/models")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["data"] || []

                  supported_models = models.map do |model|
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

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from X.AI API for provider #{provider.id}"
                  return true
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching Grok models: #{e.message}, falling back to static models"
              end
            end

            handle_sync_failure(provider, "Failed to sync Grok models: no valid credentials or API error")
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
