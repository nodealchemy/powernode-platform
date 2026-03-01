# frozen_string_literal: true

module Ai
  module Autonomy
    class PricingSyncService
      LITELLM_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
      HTTP_TIMEOUT = 30

      # Known provider prefixes in LiteLLM keys
      PROVIDER_PREFIXES = %w[openai/ anthropic/ azure/ google/ groq/ mistral/ cohere/ xai/ together_ai/ bedrock/].freeze

      class << self
        # Full sync: fetch from LiteLLM, upsert DB, propagate to providers
        def sync!
          result = { synced: 0, failed: 0, errors: [], source: nil }

          begin
            litellm_data = fetch_litellm_pricing
            if litellm_data
              result[:source] = "litellm"
              process_litellm_data(litellm_data, result)
            else
              result[:source] = "constant_fallback"
              seed_from_constant(result)
            end
          rescue StandardError => e
            Rails.logger.error("[PricingSync] Sync failed: #{e.message}")
            result[:errors] << e.message
            result[:source] = "constant_fallback"
            seed_from_constant(result)
          end

          propagate_to_providers
          result
        end

        # Look up pricing for a model, DB-backed with constant fallback
        def pricing_for(model_id)
          return nil unless model_id.is_a?(String)

          # 1. Exact match on DB
          db_pricing = Ai::ModelPricing.find_by(model_id: model_id)
          return db_pricing.pricing_hash if db_pricing

          # 2. Prefix match on DB
          prefix_match = Ai::ModelPricing.where("? LIKE model_id || '%'", model_id).order(model_id: :desc).first
          return prefix_match.pricing_hash if prefix_match

          # 3. Fall back to constant
          Ai::ProviderManagementService::MODEL_PRICING[model_id] ||
            Ai::ProviderManagementService::MODEL_PRICING.find { |key, _| model_id.start_with?(key) }&.last
        end

        private

        def fetch_litellm_pricing
          uri = URI.parse(LITELLM_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = HTTP_TIMEOUT
          http.read_timeout = HTTP_TIMEOUT

          request = Net::HTTP::Get.new(uri.request_uri)
          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            Rails.logger.warn("[PricingSync] LiteLLM fetch failed: HTTP #{response.code}")
            return nil
          end

          JSON.parse(response.body)
        rescue StandardError => e
          Rails.logger.warn("[PricingSync] LiteLLM fetch error: #{e.message}")
          nil
        end

        def process_litellm_data(data, result)
          # Build a set of model IDs we care about (from our constant + existing DB records)
          known_models = Set.new(Ai::ProviderManagementService::MODEL_PRICING.keys)
          known_models.merge(Ai::ModelPricing.pluck(:model_id))

          records_to_upsert = []

          data.each do |raw_key, model_data|
            next unless model_data.is_a?(Hash)
            next unless model_data["input_cost_per_token"] || model_data["output_cost_per_token"]

            # Strip provider prefix from LiteLLM key
            model_id = strip_provider_prefix(raw_key)
            provider_type = detect_provider_type(raw_key, model_data)

            # Only process models we already track, or all if we have fewer than 10
            next unless known_models.include?(model_id) || Ai::ModelPricing.count < 10 || known_models.any? { |k| model_id.start_with?(k) || k.start_with?(model_id) }

            input_per_1k = (model_data["input_cost_per_token"].to_f * 1000).round(8)
            output_per_1k = (model_data["output_cost_per_token"].to_f * 1000).round(8)
            cached_per_1k = ((model_data["cache_read_input_token_cost"] || 0).to_f * 1000).round(8)

            next if input_per_1k <= 0 && output_per_1k <= 0

            records_to_upsert << {
              model_id: model_id,
              provider_type: provider_type,
              input_per_1k: input_per_1k,
              output_per_1k: output_per_1k,
              cached_input_per_1k: cached_per_1k,
              tier: classify_tier(input_per_1k),
              source: "litellm",
              last_synced_at: Time.current
            }
          end

          upsert_pricing_records(records_to_upsert, result)
        end

        def upsert_pricing_records(records, result)
          records.each do |attrs|
            existing = Ai::ModelPricing.find_by(model_id: attrs[:model_id], provider_type: attrs[:provider_type])

            # Never overwrite manual overrides
            if existing&.source == "manual"
              result[:failed] += 1
              next
            end

            if existing
              # Store previous values for audit
              previous = { input: existing.input_per_1k.to_f, output: existing.output_per_1k.to_f }
              existing.update!(
                attrs.except(:model_id, :provider_type).merge(
                  metadata: (existing.metadata || {}).merge("previous" => previous)
                )
              )

              # Log significant price changes (>5%)
              if previous[:input] > 0
                delta_pct = ((attrs[:input_per_1k] - previous[:input]).abs / previous[:input] * 100).round(1)
                if delta_pct > 5
                  Rails.logger.info("[PricingSync] Price change: #{attrs[:model_id]} input #{previous[:input]} -> #{attrs[:input_per_1k]} (#{delta_pct}%)")
                end
              end
            else
              Ai::ModelPricing.create!(attrs.merge(metadata: {}))
            end

            result[:synced] += 1
          rescue StandardError => e
            result[:failed] += 1
            result[:errors] << "#{attrs[:model_id]}: #{e.message}"
          end
        end

        def seed_from_constant(result)
          Ai::ProviderManagementService::MODEL_PRICING.each do |model_id, pricing|
            existing = Ai::ModelPricing.find_by(model_id: model_id)
            next if existing # Don't overwrite existing records (they're the last-known-good)

            provider_type = detect_provider_from_model_id(model_id)

            Ai::ModelPricing.create!(
              model_id: model_id,
              provider_type: provider_type,
              input_per_1k: pricing["input"],
              output_per_1k: pricing["output"],
              cached_input_per_1k: pricing["cached_input"] || 0,
              tier: pricing["tier"],
              source: "constant_fallback",
              last_synced_at: Time.current,
              metadata: {}
            )
            result[:synced] += 1
          rescue StandardError => e
            result[:failed] += 1
            result[:errors] << "#{model_id}: #{e.message}"
          end
        end

        def propagate_to_providers
          Ai::Provider.where(is_active: true).find_each do |provider|
            models = provider.supported_models || []
            updated = false

            models.each do |model|
              model_name = model["id"] || model["name"]
              next unless model_name

              pricing = pricing_for(model_name)
              next unless pricing

              model["cost_per_1k_tokens"] = {
                "input" => pricing["input"],
                "output" => pricing["output"],
                "cached_input" => pricing["cached_input"]
              }
              updated = true
            end

            provider.update_columns(supported_models: models) if updated
          end
        rescue StandardError => e
          Rails.logger.error("[PricingSync] Failed to propagate pricing to providers: #{e.message}")
        end

        def strip_provider_prefix(key)
          PROVIDER_PREFIXES.each do |prefix|
            return key.delete_prefix(prefix) if key.start_with?(prefix)
          end
          key
        end

        def detect_provider_type(raw_key, model_data)
          return "openai" if raw_key.start_with?("openai/") || raw_key.match?(/^gpt-|^o[34]/)
          return "anthropic" if raw_key.start_with?("anthropic/") || raw_key.match?(/^claude/)
          return "google" if raw_key.start_with?("google/") || raw_key.match?(/^gemini/)
          return "groq" if raw_key.start_with?("groq/")
          return "mistral" if raw_key.start_with?("mistral/") || raw_key.match?(/^mistral|^codestral/)
          return "cohere" if raw_key.start_with?("cohere/") || raw_key.match?(/^command/)
          return "xai" if raw_key.start_with?("xai/") || raw_key.match?(/^grok/)

          model_data["litellm_provider"]&.downcase || "unknown"
        end

        def detect_provider_from_model_id(model_id)
          case model_id
          when /^gpt-|^o[34]/ then "openai"
          when /^claude/ then "anthropic"
          when /^gemini/ then "google"
          when /^grok/ then "xai"
          when /^llama|^mixtral/ then "groq"
          when /^mistral|^codestral/ then "mistral"
          when /^command/ then "cohere"
          else "unknown"
          end
        end

        def classify_tier(input_per_1k)
          if input_per_1k >= 0.003 then "premium"
          elsif input_per_1k >= 0.0005 then "standard"
          else "economy"
          end
        end
      end
    end
  end
end
