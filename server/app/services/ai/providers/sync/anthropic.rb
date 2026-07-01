# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Anthropic
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_anthropic_models(provider)
            # Try to fetch models from Anthropic API dynamically
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            # No credential yet = setup state, not failure — defer the sync
            # instead of deactivating a provider that was just created.
            if credential.nil?
              return handle_sync_skipped(provider,
                                         "no active credential for Anthropic — model sync deferred until credentials are configured")
            end

            if credential
              begin
                api_key = credential.credentials["api_key"]
                response = HTTP.headers(
                  "x-api-key" => api_key,
                  "anthropic-version" => "2023-06-01",
                  "Content-Type" => "application/json"
                ).timeout(15).get("https://api.anthropic.com/v1/models")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["data"] || []

                  supported_models = models.map do |model|
                    {
                      "name" => format_anthropic_model_name(model["id"]),
                      "id" => model["id"],
                      "context_length" => anthropic_context_length(model["id"]),
                      "max_output_tokens" => extract_max_output_tokens(model["id"]),
                      "description" => model["display_name"] || format_anthropic_model_name(model["id"]),
                      "capabilities" => extract_anthropic_capabilities(model["id"]),
                      "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                      "display_name" => model["display_name"],
                      "created_at" => model["created_at"]
                    }
                  end

                  # Sort by model name (newest first based on naming convention)
                  supported_models.sort_by! { |m| -anthropic_model_sort_priority(m["id"]) }

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from Anthropic API for provider #{provider.id}"
                  return true
                else
                  Rails.logger.warn "Anthropic API returned #{response.status}, falling back to static models"
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching Anthropic models: #{e.message}, falling back to static models"
              end
            end

            # Sync failed - deactivate provider and clear models
            handle_sync_failure(provider, "Failed to sync Anthropic models: no valid credentials or API error")
          end

          def format_anthropic_model_name(model_id)
            # Convert model ID to human-readable name
            # e.g., "claude-opus-4-5-20251101" -> "Claude Opus 4.5"
            return model_id unless model_id.is_a?(String)

            name = model_id
              .gsub(/-\d{8}$/, "")           # Remove date suffix
              .gsub("-", " ")                 # Replace dashes with spaces
              .gsub(/(\d) (\d)/, '\1.\2')     # "4 5" -> "4.5"
              .split.map(&:capitalize).join(" ")

            name.gsub("Claude", "Claude")     # Ensure proper casing
          end

          # Fable/Mythos and the current generation (Opus 4.6+, Sonnet 4.6+/5)
          # carry a 1M-token context window; older Anthropic models are 200K.
          def anthropic_context_length(model_id)
            return 1_000_000 if fable_family?(model_id) || current_generation?(model_id)
            200000
          end

          def extract_max_output_tokens(model_id)
            # Fable/Mythos + current generation: 128K. Haiku 4.5 and Sonnet 4.5:
            # 64K. Older Opus: 32K. Everything else keeps the legacy 8K fallback.
            return 128000 if fable_family?(model_id) || current_generation?(model_id)
            return 64000 if model_id.include?("haiku-4-5") || model_id.include?("sonnet-4-5")
            return 32000 if model_id.include?("opus")
            8192
          end

          # Current-generation ids sharing the 1M/128K envelope (prefix-based,
          # mirroring Ai::Llm::ModelCapabilities::ADAPTIVE_ONLY_PREFIXES plus the
          # 4-6 family, which shares the envelope but still allows sampling).
          def current_generation?(model_id)
            %w[claude-opus-4-8 claude-opus-4-7 claude-opus-4-6 claude-sonnet-5 claude-sonnet-4-6]
              .any? { |prefix| model_id.start_with?(prefix) }
          end

          def extract_anthropic_capabilities(model_id)
            capabilities = [ "text_generation", "chat", "vision" ]
            fable = fable_family?(model_id)
            capabilities << "code_generation" if fable || model_id.include?("opus") || model_id.include?("sonnet")
            capabilities << "extended_thinking" if fable || model_id.include?("opus")
            capabilities << "reasoning" if fable
            capabilities
          end

          def fable_family?(model_id)
            model_id.include?("fable") || model_id.include?("mythos")
          end

          def anthropic_model_sort_priority(model_id)
            # Higher priority = listed first. Newest generation first within each
            # tier; retired Claude-3-era branches removed (those ids 404 now).
            return 120 if fable_family?(model_id)
            return 110 if model_id.include?("opus-4-8")
            return 105 if model_id.include?("opus-4-7")
            return 100 if model_id.include?("opus-4-6")
            return 95 if model_id.include?("opus-4-5")
            return 90 if model_id.include?("opus")
            return 85 if model_id.include?("sonnet-5")
            return 80 if model_id.include?("sonnet-4-6")
            return 75 if model_id.include?("sonnet-4-5")
            return 70 if model_id.include?("sonnet")
            return 50 if model_id.include?("haiku-4-5")
            return 40 if model_id.include?("haiku")
            0
          end
        end
      end
    end
  end
end
