# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Google
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_google_models(provider)
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            if credential
              begin
                api_key = credential.credentials["api_key"]
                # Google AI Studio API endpoint for listing models
                response = HTTP.timeout(15).get("https://generativelanguage.googleapis.com/v1beta/models?key=#{api_key}")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["models"] || []

                  # Filter to generative models only
                  generative_models = models.select { |m| m["name"]&.include?("gemini") }

                  supported_models = generative_models.map do |model|
                    model_id = model["name"]&.split("/")&.last || model["name"]
                    {
                      "name" => model["displayName"] || format_google_model_name(model_id),
                      "id" => model_id,
                      "context_length" => model["inputTokenLimit"] || 1048576,
                      "max_output_tokens" => model["outputTokenLimit"] || 8192,
                      "description" => model["description"] || model["displayName"],
                      "capabilities" => google_capabilities(model_id),
                      "cost_per_1k_tokens" => model_pricing_for(model_id),
                      "supports_thinking" => model["supportThinking"] || false,
                      "max_temperature" => model["maxTemperature"],
                      "supported_methods" => model["supportedGenerationMethods"]
                    }
                  end

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from Google API for provider #{provider.id}"
                  return true
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching Google models: #{e.message}, falling back to static models"
              end
            end

            handle_sync_failure(provider, "Failed to sync Google models: no valid credentials or API error")
          end

          def format_google_model_name(model_id)
            model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
          end

          def google_capabilities(model_id)
            caps = %w[text_generation chat vision]
            caps << "audio" if model_id.include?("1.5") || model_id.include?("2.0")
            caps << "code_execution" if model_id.include?("2.0")
            caps
          end
        end
      end
    end
  end
end
