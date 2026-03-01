# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Ollama
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_ollama_models(provider)
            base_url = provider.api_base_url.to_s.chomp("/")
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            # Build possible endpoint URLs (try multiple patterns)
            # Standard Ollama: http://localhost:11434/api/tags
            # Open WebUI: https://host/ollama/api/tags (requires auth)
            # Open WebUI alt: https://host/api/tags (with /api base)
            endpoints = []

            if base_url.end_with?("/api")
              # Base URL already includes /api
              endpoints << { url: "#{base_url}/tags", auth: false }
              endpoints << { url: "#{base_url}/tags", auth: true }
            else
              # Standard Ollama endpoint first
              endpoints << { url: "#{base_url}/api/tags", auth: false }
              # Open WebUI endpoint (requires auth)
              endpoints << { url: "#{base_url}/ollama/api/tags", auth: true }
              # Retry standard with auth
              endpoints << { url: "#{base_url}/api/tags", auth: true }
            end

            api_data = nil

            endpoints.each do |endpoint|
              begin
                http_client = HTTP.timeout(10)

                # Add authentication if needed and credential exists
                if endpoint[:auth] && credential
                  api_key = credential.credentials&.dig("api_key")
                  if api_key.present?
                    http_client = http_client.headers("Authorization" => "Bearer #{api_key}")
                  end
                end

                response = http_client.get(endpoint[:url])

                if response.status.success?
                  body = response.body.to_s
                  # Verify it's JSON, not HTML
                  if body.start_with?("{") || body.start_with?("[")
                    api_data = JSON.parse(body)
                    Rails.logger.info "Ollama sync succeeded with endpoint: #{endpoint[:url]}"
                    break
                  end
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.debug "Ollama endpoint #{endpoint[:url]} failed: #{e.message}"
                next
              end
            end

            if api_data
              models = api_data["models"] || []

              # Transform Ollama API response to our model format
              supported_models = models.map do |model|
                details = model["details"] || {}
                {
                  "name" => model["name"]&.split(":")&.first&.capitalize || model["name"],
                  "id" => model["name"],
                  "context_length" => details["parameter_size"] || 4096,
                  "description" => "#{model['name']} - Size: #{format_model_size(model['size'])}",
                  "cost_per_1k_tokens" => { "input" => 0, "output" => 0 },
                  "size_bytes" => model["size"],
                  "family" => details["family"],
                  "parameter_size" => details["parameter_size"],
                  "quantization_level" => details["quantization_level"],
                  "modified_at" => model["modified_at"],
                  "digest" => model["digest"],
                  "format" => details["format"]
                }
              end

              provider.update(supported_models: supported_models)
              Rails.logger.info "Successfully synced #{supported_models.length} models for Ollama provider #{provider.id}"
            else
              Rails.logger.error "Failed to fetch models from any Ollama endpoint for provider #{provider.id} (base_url: #{base_url})"
              handle_sync_failure(provider, "Could not connect to Ollama API at #{base_url}")
            end
          rescue HTTP::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
            Rails.logger.error "Error syncing Ollama models: #{e.message}"
            handle_sync_failure(provider, "Could not connect to Ollama API: #{e.message}")
          end
        end
      end
    end
  end
end
