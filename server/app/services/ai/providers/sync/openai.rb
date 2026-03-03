# frozen_string_literal: true

module Ai
  module Providers
    module Sync
      module Openai
        extend ActiveSupport::Concern

        class_methods do
          private

          def sync_openai_models(provider)
            credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

            if credential
              begin
                api_key = credential.credentials["api_key"]
                response = HTTP.headers(
                  "Authorization" => "Bearer #{api_key}",
                  "Content-Type" => "application/json"
                ).timeout(15).get("https://api.openai.com/v1/models")

                if response.status.success?
                  api_data = JSON.parse(response.body.to_s)
                  models = api_data["data"] || []

                  # Filter to chat/completion models (exclude embeddings, whisper, etc.)
                  chat_models = models.select { |m| openai_chat_model?(m["id"]) }

                  supported_models = chat_models.map do |model|
                    {
                      "name" => format_openai_model_name(model["id"]),
                      "id" => model["id"],
                      "context_length" => openai_context_length(model["id"]),
                      "max_output_tokens" => openai_max_output(model["id"]),
                      "description" => openai_model_description(model["id"]),
                      "capabilities" => openai_capabilities(model["id"]),
                      "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                      "owned_by" => model["owned_by"],
                      "created_at" => model["created"] ? Time.at(model["created"]).iso8601 : nil
                    }
                  end

                  # Also collect image generation models (DALL-E)
                  image_models = models.select { |m| openai_image_model?(m["id"]) }
                  image_models.each do |model|
                    supported_models << {
                      "name" => format_openai_model_name(model["id"]),
                      "id" => model["id"],
                      "context_length" => 0,
                      "max_output_tokens" => 0,
                      "description" => openai_image_model_description(model["id"]),
                      "capabilities" => %w[image_generation],
                      "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                      "owned_by" => model["owned_by"],
                      "created_at" => model["created"] ? Time.at(model["created"]).iso8601 : nil
                    }
                  end

                  supported_models.sort_by! { |m| -openai_model_priority(m["id"]) }

                  provider.update(supported_models: supported_models)
                  Rails.logger.info "Successfully synced #{supported_models.length} models from OpenAI API for provider #{provider.id}"
                  return true
                end
              rescue HTTP::Error, JSON::ParserError => e
                Rails.logger.error "Error fetching OpenAI models: #{e.message}, falling back to static models"
              end
            end

            handle_sync_failure(provider, "Failed to sync OpenAI models: no valid credentials or API error")
          end

          def openai_chat_model?(model_id)
            model_id.match?(/^(gpt-4|gpt-3\.5|o1|o3|o4|chatgpt)/i) && !model_id.include?("instruct")
          end

          def openai_image_model?(model_id)
            model_id.match?(/^dall-e/i)
          end

          def format_openai_model_name(model_id)
            model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
              .gsub("Gpt", "GPT").gsub("4o", "4o").gsub("3.5", "3.5")
          end

          def openai_context_length(model_id)
            return 200000 if model_id.include?("o1") || model_id.include?("o3")
            return 128000 if model_id.include?("gpt-4o") || model_id.include?("gpt-4-turbo")
            return 16385 if model_id.include?("gpt-3.5")
            8192
          end

          def openai_max_output(model_id)
            return 100000 if model_id.include?("o1") || model_id.include?("o3")
            return 16384 if model_id.include?("gpt-4o")
            4096
          end

          def openai_capabilities(model_id)
            caps = %w[text_generation chat function_calling]
            caps << "vision" if model_id.include?("gpt-4o") || model_id.include?("gpt-4-turbo") || model_id.include?("o1") || model_id.include?("o3")
            caps << "reasoning" if model_id.include?("o1") || model_id.include?("o3")
            caps
          end

          def openai_model_description(model_id)
            return "Advanced reasoning model" if model_id.include?("o1") || model_id.include?("o3")
            return "Most advanced multimodal model" if model_id == "gpt-4o"
            return "Affordable and intelligent small model" if model_id.include?("gpt-4o-mini")
            return "GPT-4 Turbo with vision" if model_id.include?("gpt-4-turbo")
            return "Fast and efficient model" if model_id.include?("gpt-3.5")
            "OpenAI language model"
          end

          def openai_image_model_description(model_id)
            return "Most capable image generation model with highest quality" if model_id == "dall-e-3"
            return "Fast image generation and editing" if model_id == "dall-e-2"
            "OpenAI image generation model"
          end

          def openai_model_priority(model_id)
            return 100 if model_id == "gpt-4o"
            return 95 if model_id.include?("o3")
            return 90 if model_id.include?("o1") && !model_id.include?("mini")
            return 85 if model_id.include?("o1-mini")
            return 80 if model_id.include?("gpt-4o-mini")
            return 70 if model_id.include?("gpt-4-turbo")
            return 60 if model_id.include?("gpt-4")
            return 50 if model_id.include?("gpt-3.5")
            return 40 if model_id == "dall-e-3"
            return 30 if model_id == "dall-e-2"
            0
          end
        end
      end
    end
  end
end
