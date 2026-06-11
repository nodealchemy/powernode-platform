# frozen_string_literal: true

class Ai::ProviderManagementService
  module ModelSync
    extend ActiveSupport::Concern

    class_methods do
      # Look up pricing for a model by exact match, then prefix match
      # DB-backed pricing (populated by PricingSyncService) takes precedence
      def model_pricing_for(model_id)
        return nil unless model_id.is_a?(String)

        # 1. DB-backed pricing (populated by PricingSyncService)
        db_pricing = ::Ai::ModelPricing.find_by(model_id: model_id)&.pricing_hash
        return db_pricing if db_pricing

        # 2. Prefix match on DB
        prefix_match = ::Ai::ModelPricing.where("? LIKE model_id || '%'", model_id).order(model_id: :desc).first&.pricing_hash
        return prefix_match if prefix_match

        # 3. Fall back to hardcoded constant (last resort)
        MODEL_PRICING[model_id] ||
          MODEL_PRICING.find { |key, _| model_id.start_with?(key) }&.last
      end

      # Sync models for all active providers
      def sync_all_providers(force_refresh: false)
        results = { synced: 0, failed: 0, skipped: 0, errors: [] }

        Ai::Provider.where(is_active: true).find_each do |provider|
          if sync_provider_models(provider, force_refresh: force_refresh)
            results[:synced] += 1
          else
            results[:failed] += 1
            results[:errors] << { provider_id: provider.id, name: provider.name }
          end
        rescue StandardError => e
          Rails.logger.error "Failed to sync provider #{provider.id}: #{e.message}"
          results[:failed] += 1
          results[:errors] << { provider_id: provider.id, name: provider.name, error: e.message }
        end

        results
      end

      # Sync providers flagged sync-pending by their create/update callbacks.
      # Called by the worker's short-interval pull sweep
      # (AiProviderPendingSyncJob → POST internal/ai/providers/sync_pending).
      # Each flag is claimed BEFORE the attempt: a permanently failing
      # provider must not wedge the sweep into retrying every tick — the
      # daily full sweep is the retry path.
      def sync_pending_providers
        results = { synced: 0, failed: 0, errors: [] }

        Ai::Provider.model_sync_pending.find_each do |provider|
          provider.clear_model_sync_pending!

          if sync_provider_models(provider, force_refresh: true)
            results[:synced] += 1
          else
            results[:failed] += 1
            results[:errors] << { provider_id: provider.id, name: provider.name }
          end
        rescue StandardError => e
          Rails.logger.error "Failed pending model sync for provider #{provider.id}: #{e.message}"
          results[:failed] += 1
          results[:errors] << { provider_id: provider.id, name: provider.name, error: e.message }
        end

        results
      end

      # Sync models for a specific provider (cached for 24 hours)
      # Runs for inactive providers too: syncing only reads from the upstream
      # API, and an inactive provider needs its models populated before the
      # supported_models presence validation will allow activating it.
      def sync_provider_models(provider, force_refresh: false)
        cache_key = "ai:provider_models:#{provider.id}"

        # Use cache unless force refresh is requested
        unless force_refresh
          cached = Rails.cache.read(cache_key)
          return true if cached.present?
        end

        begin
          # Use provider_type for reliable matching (slug can vary)
          synced = case provider.provider_type&.downcase
          when "ollama"
            sync_ollama_models(provider)
          when "openai"
            sync_openai_models(provider)
          when "anthropic"
            sync_anthropic_models(provider)
          when "google"
            sync_google_models(provider)
          when "azure", "azure_openai"
            sync_azure_models(provider)
          when "groq"
            sync_groq_models(provider)
          when "grok", "xai", "x.ai", "x-ai"
            sync_grok_models(provider)
          when "mistral"
            sync_mistral_models(provider)
          when "cohere"
            sync_cohere_models(provider)
          else
            # Also check slug for custom providers that might use standard slugs
            case provider.slug&.downcase
            when "ollama", "remote-ollama-server"
              sync_ollama_models(provider)
            when "openai"
              sync_openai_models(provider)
            when "anthropic"
              sync_anthropic_models(provider)
            when "grok", "grok-xai", "xai", "x-ai", "x.ai"
              sync_grok_models(provider)
            when "google", "gemini"
              sync_google_models(provider)
            when "groq"
              sync_groq_models(provider)
            when "mistral"
              sync_mistral_models(provider)
            when "cohere"
              sync_cohere_models(provider)
            when "azure", "azure-openai"
              sync_azure_models(provider)
            else
              sync_generic_models(provider)
            end
          end

          # A deferred sync (e.g. no credential yet — handle_sync_skipped)
          # returns false WITHOUT raising: don't cache it as a success, or the
          # 24h cache would swallow the first real sync after credentials are
          # configured.
          return false unless synced

          # Health status is now computed via the model's health_status method
          # Cache the successful sync
          Rails.cache.write(cache_key, true, expires_in: PROVIDER_MODELS_CACHE_TTL)
          true
        rescue StandardError => e
          Rails.logger.error "Failed to sync models for provider #{provider.id}: #{e.message}"
          record_sync_failure(provider, e.message)
        end
      end

      # Invalidate provider models cache
      def invalidate_provider_models_cache(provider_id)
        Rails.cache.delete("ai:provider_models:#{provider_id}")
      end

      # Get usage summary for a provider within a specific account
      # Queries real Ai::AgentExecution data for accurate metrics
      def provider_usage_summary(provider, account, period)
        end_date = Time.current
        start_date = end_date - period

        # Query real execution data from agents using this provider
        executions = fetch_provider_executions(provider, account, start_date, end_date)

        # Calculate aggregated metrics
        total_requests = executions.count
        successful_requests = executions.where(status: "completed").count
        failed_requests = executions.where(status: "failed").count

        # Token and cost calculations from execution metadata
        token_stats = calculate_token_stats(executions)
        cost_stats = calculate_cost_stats(executions)

        # Response time calculations
        response_time_stats = calculate_response_time_stats(executions)

        # Calculate success rate safely
        success_rate = total_requests > 0 ? (successful_requests.to_f / total_requests * 100).round(1) : 0.0

        {
          provider_id: provider.id,
          provider_name: provider.name,
          period_start: start_date,
          period_end: end_date,
          period_days: (period.to_i / 1.day.to_i),
          total_requests: total_requests,
          successful_requests: successful_requests,
          failed_requests: failed_requests,
          total_tokens: token_stats[:total],
          prompt_tokens: token_stats[:prompt],
          completion_tokens: token_stats[:completion],
          total_cost: cost_stats[:total].round(2),
          average_response_time_ms: response_time_stats[:average].round,
          min_response_time_ms: response_time_stats[:min],
          max_response_time_ms: response_time_stats[:max],
          success_rate: success_rate,
          daily_breakdown: generate_real_daily_breakdown(provider, account, start_date, end_date)
        }
      end

      private

      # Fetch executions for a provider within an account
      def fetch_provider_executions(provider, account, start_date, end_date)
        # Get agents that use this provider within the account
        agent_ids = ::Ai::Agent.where(account: account, provider: provider).pluck(:id)

        return ::Ai::AgentExecution.none if agent_ids.empty?

        ::Ai::AgentExecution.where(ai_agent_id: agent_ids)
                           .where(created_at: start_date..end_date)
      end

      # Calculate token statistics from executions
      def calculate_token_stats(executions)
        return { total: 0, prompt: 0, completion: 0 } if executions.empty?

        # Sum tokens from execution metadata (stored in result or metadata columns)
        stats = { total: 0, prompt: 0, completion: 0 }

        executions.find_each do |execution|
          # Try to extract token usage from result or metadata
          metadata = execution.output_data.is_a?(Hash) ? execution.output_data : {}
          usage = metadata["usage"] || metadata["token_usage"] || {}

          stats[:prompt] += (usage["prompt_tokens"] || usage["input_tokens"] || 0).to_i
          stats[:completion] += (usage["completion_tokens"] || usage["output_tokens"] || 0).to_i
        end

        stats[:total] = stats[:prompt] + stats[:completion]
        stats
      end

      # Calculate cost statistics from executions
      def calculate_cost_stats(executions)
        return { total: 0.0 } if executions.empty?

        total_cost = 0.0

        executions.find_each do |execution|
          metadata = execution.output_data.is_a?(Hash) ? execution.output_data : {}
          cost = metadata["cost"] || metadata["cost_estimate"] || 0.0
          total_cost += cost.to_f
        end

        { total: total_cost }
      end

      # Calculate response time statistics
      def calculate_response_time_stats(executions)
        return { average: 0, min: 0, max: 0 } if executions.empty?

        # Use duration_ms if available, otherwise calculate from timestamps
        durations = []

        executions.find_each do |execution|
          duration = if execution.respond_to?(:duration_ms) && execution.duration_ms.present?
                      execution.duration_ms
          elsif execution.started_at && execution.completed_at
                      ((execution.completed_at - execution.started_at) * 1000).to_i
          end

          durations << duration if duration && duration > 0
        end

        return { average: 0, min: 0, max: 0 } if durations.empty?

        {
          average: durations.sum.to_f / durations.size,
          min: durations.min,
          max: durations.max
        }
      end

      # Generate real daily breakdown from actual execution data
      def generate_real_daily_breakdown(provider, account, start_date, end_date)
        breakdown = []
        current_date = start_date.beginning_of_day

        # Get all agent IDs for this provider/account combo once
        agent_ids = ::Ai::Agent.where(account: account, provider: provider).pluck(:id)

        while current_date <= end_date
          day_end = current_date.end_of_day

          if agent_ids.any?
            day_executions = ::Ai::AgentExecution.where(ai_agent_id: agent_ids)
                                                .where(created_at: current_date..day_end)

            day_requests = day_executions.count
            day_token_stats = calculate_token_stats(day_executions)
            day_cost_stats = calculate_cost_stats(day_executions)
            day_response_stats = calculate_response_time_stats(day_executions)

            breakdown << {
              date: current_date.to_date,
              requests: day_requests,
              successful: day_executions.where(status: "completed").count,
              failed: day_executions.where(status: "failed").count,
              tokens: day_token_stats[:total],
              cost: day_cost_stats[:total].round(2),
              avg_response_time: day_response_stats[:average].round
            }
          else
            # No agents configured - return zero values
            breakdown << {
              date: current_date.to_date,
              requests: 0,
              successful: 0,
              failed: 0,
              tokens: 0,
              cost: 0.0,
              avg_response_time: 0
            }
          end

          current_date += 1.day
        end

        breakdown
      end

      # Record the sync failure reason on provider metadata for operator
      # visibility. update_all bypasses validations: a provider with no synced
      # models cannot satisfy the supported_models presence validation.
      # Returns false so it can be the tail call of a failure path.
      def record_sync_failure(provider, error_message, **extra_columns)
        current_metadata = provider.metadata || {}
        current_metadata["last_sync_error"] = error_message
        current_metadata["last_sync_failed_at"] = Time.current.iso8601

        Ai::Provider.where(id: provider.id).update_all(
          { metadata: current_metadata }.merge(extra_columns)
        )
        provider.reload
        false
      end

      # Handle sync failure: clear models, deactivate provider, raise error
      def handle_sync_failure(provider, error_message)
        Rails.logger.error "[ProviderSync] #{error_message} (provider: #{provider.id} / #{provider.name})"

        # We intentionally want 0 models and a deactivated provider on a
        # failed fetch
        record_sync_failure(provider, error_message, supported_models: [], is_active: false)

        raise StandardError, error_message
      end

      # A missing credential is "not configured yet", not a provider failure —
      # the create-time after_commit sync runs before credentials can possibly
      # be attached, so deactivating here bricked every freshly created
      # provider (and silently disabled factory providers across the test
      # suite). Defer instead: keep is_active and the seeded supported_models
      # untouched, stamp the skip reason, and let the next sync (post-
      # credential) do the real fetch.
      def handle_sync_skipped(provider, reason)
        Rails.logger.info "[ProviderSync] sync deferred for provider #{provider.id} / #{provider.name}: #{reason}"

        current_metadata = provider.metadata || {}
        current_metadata["last_sync_skipped_at"] = Time.current.iso8601
        current_metadata["last_sync_skipped_reason"] = reason
        Ai::Provider.where(id: provider.id).update_all(metadata: current_metadata)
        provider.reload
        false
      end

      # Shared fetch path for Bearer-auth providers that expose a JSON model
      # list (OpenAI-compatible and friends). Yields the parsed model array for
      # provider-specific mapping; the block returns the supported_models array
      # to persist. Raises via handle_sync_failure on missing credentials /
      # non-success / HTTP+JSON errors — identical fall-through to the
      # per-provider methods it replaces. success_label lets a provider log a
      # different name on success than on failure (e.g. X.AI vs Grok).
      def sync_bearer_models(provider, url:, label:, models_key: "data", success_label: nil)
        success_label ||= label
        credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

        if credential.nil?
          return handle_sync_skipped(provider,
                                     "no active credential for #{label} — model sync deferred until credentials are configured")
        end

        if credential
          begin
            api_key = credential.credentials["api_key"]
            response = HTTP.headers(
              "Authorization" => "Bearer #{api_key}",
              "Content-Type" => "application/json"
            ).timeout(15).get(url)

            if response.status.success?
              api_data = JSON.parse(response.body.to_s)
              supported_models = yield(api_data[models_key] || [])

              provider.update(supported_models: supported_models)
              Rails.logger.info "Successfully synced #{supported_models.length} models from #{success_label} API for provider #{provider.id}"
              return true
            end
          rescue HTTP::Error, JSON::ParserError => e
            Rails.logger.error "Error fetching #{label} models: #{e.message}, falling back to static models"
          end
        end

        handle_sync_failure(provider, "Failed to sync #{label} models: no valid credentials or API error")
      end

      def format_model_size(size_bytes)
        return "Unknown" unless size_bytes

        # Convert bytes to human-readable format
        units = [ "B", "KB", "MB", "GB", "TB" ]
        size = size_bytes.to_f
        unit_index = 0

        while size >= 1024 && unit_index < units.length - 1
          size /= 1024
          unit_index += 1
        end

        "#{size.round(1)} #{units[unit_index]}"
      end
    end
  end
end
