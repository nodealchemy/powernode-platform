# frozen_string_literal: true

module Ai
  module Tools
    # LLM PROVIDERS AND THE MODEL CATALOG, READ-ONLY (audit remedy 18).
    #
    # The `system_*_provider*` family is CLOUD/INFRA providers — a false
    # positive the audit called out by name. The LLM providers an operations
    # agent actually needs ("which models can I route to, and is that provider
    # configured") had zero MCP verbs while REST exposed full CRUD.
    #
    # ── CREDENTIALS NEVER CROSS THIS BOUNDARY ───────────────────────────────
    #
    # `Ai::Provider#credentials` (concerns/ai/provider/configurable.rb:21-32)
    # returns the DECRYPTED credential hash. It is never called here, and
    # nothing in this file reads `Ai::ProviderCredential#credentials`,
    # `encrypted_credentials`, `encryption_key_id` or `vault_path`.
    #
    # What the caller gets instead is `credential_status`: booleans and counts
    # derived from the credential rows — configured, active count, expiry,
    # last-test outcome. That answers "can this provider be used" without
    # answering "with what". `last_error` is also withheld: a provider's error
    # body can echo the key that was rejected.
    #
    # `#configuration` masks `api_key` and would be safer than `#credentials`,
    # but "safer" is not the bar for a surface an agent can call — neither is
    # here. The serializers below are ALLOW-LISTS, so a column added to
    # `ai_providers` tomorrow does not appear by default.
    class ProviderReadTool < BaseTool
      REQUIRED_PERMISSION = "ai.providers.read"

      ACTION_PERMISSIONS = {
        "list_llm_providers" => "ai.providers.read",
        "get_llm_provider" => "ai.providers.read",
        "list_models" => "ai.providers.read"
      }.freeze

      declare_action "list_llm_providers", mutating: false
      declare_action "get_llm_provider", mutating: false
      declare_action "list_models", mutating: false

      def self.definition
        {
          name: "provider_read",
          description: "Read-only view of the account's LLM providers and the model catalog: " \
                       "capabilities, endpoints, whether credentials are configured, and per-model " \
                       "pricing. Never returns credentials or API keys.",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "list_llm_providers" => {
            description: "List this account's LLM providers with their type, capabilities and whether " \
                         "a working credential is configured. Credential VALUES are never returned. " \
                         "Requires ai.providers.read.",
            parameters: {
              active_only: { type: "boolean", required: false, description: "Only providers with is_active true" },
              provider_type: { type: "string", required: false, description: "Filter by provider_type (anthropic, openai, ...)" },
              **PAGINATION_PARAMETERS
            }
          },
          "get_llm_provider" => {
            description: "One provider in full: endpoints, capability flags, supported models, rate limits, " \
                         "default parameters and credential STATUS (configured / active count / expiry / " \
                         "last test outcome — never the credential itself). Requires ai.providers.read.",
            parameters: {
              id: { type: "string", required: false, description: "Provider id" },
              slug: { type: "string", required: false, description: "Provider slug, an alternative to id" }
            }
          },
          "list_models" => {
            description: "The model catalog: the models this account's providers declare they support, " \
                         "joined with per-1k input/output pricing where the platform has it. Use this " \
                         "before choosing a model id rather than hardcoding one. Requires ai.providers.read.",
            parameters: {
              provider_type: { type: "string", required: false, description: "Filter to one provider type" },
              with_pricing_only: { type: "boolean", required: false, description: "Only models the pricing catalog covers" }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s
        return error_result("permission denied: #{required_perm_for(action)} required") unless action_permitted?(action)

        case action
        when "list_llm_providers" then list_llm_providers(params)
        when "get_llm_provider"   then get_llm_provider(params)
        when "list_models"        then list_models(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

      def providers
        account.ai_providers.includes(:provider_credentials)
      end

      def list_llm_providers(params)
        scope = providers
        scope = scope.where(is_active: true) if truthy?(params[:active_only])
        scope = scope.where(provider_type: params[:provider_type].to_s) if params[:provider_type].present?

        paginated_result(:providers, scope, params, sort: :id, direction: :asc) { |row| serialize_provider(row) }
      end

      def get_llm_provider(params)
        row = if params[:id].present?
                providers.find_by(id: params[:id].to_s)
        elsif params[:slug].present?
                providers.find_by(slug: params[:slug].to_s)
        end
        return error_result("give either `id` or `slug`") if params[:id].blank? && params[:slug].blank?
        return error_result("provider not found in this account") unless row

        success_result(provider: serialize_provider(row, detail: true))
      end

      def list_models(params)
        scope = providers.where(is_active: true)
        scope = scope.where(provider_type: params[:provider_type].to_s) if params[:provider_type].present?

        pricing = ::Ai::ModelPricing.all.index_by { |row| row.model_id.to_s }
        rows = scope.flat_map { |provider| models_for(provider, pricing) }.uniq { |m| [ m[:provider_id], m[:model_id] ] }
        rows = rows.select { |m| m[:pricing].present? } if truthy?(params[:with_pricing_only])

        success_result(
          models: rows,
          count: rows.size,
          pricing_source: "ai_model_pricings (per 1k tokens); nil means the catalog has no row for that model"
        )
      end

      def models_for(provider, pricing)
        Array(provider.supported_models).map do |entry|
          model_id = entry.is_a?(Hash) ? (entry["id"] || entry[:id] || entry["name"] || entry[:name]).to_s : entry.to_s
          price = pricing[model_id]
          {
            provider_id: provider.id,
            provider_slug: provider.slug,
            provider_type: provider.provider_type,
            model_id: model_id,
            pricing: price && {
              input_per_1k: price.input_per_1k,
              output_per_1k: price.output_per_1k,
              cached_input_per_1k: price.cached_input_per_1k,
              tier: price.tier,
              last_synced_at: iso(price.last_synced_at)
            }
          }
        end
      end

      # ALLOW-LIST. Never `.attributes`, never `#credentials`, never
      # `#configuration` — see the class comment.
      def serialize_provider(row, detail: false)
        payload = {
          id: row.id,
          name: row.name,
          slug: row.slug,
          provider_type: row.provider_type,
          provider_identifier: row.provider_identifier,
          description: row.description,
          is_active: row.is_active,
          requires_auth: row.requires_auth,
          priority_order: row.priority_order,
          supports_streaming: row.supports_streaming,
          supports_functions: row.supports_functions,
          supports_vision: row.supports_vision,
          supports_code_execution: row.supports_code_execution,
          credential_status: credential_status(row)
        }
        return payload unless detail

        payload.merge(
          api_base_url: row.api_base_url,
          api_endpoint: row.api_endpoint,
          documentation_url: row.documentation_url,
          status_url: row.status_url,
          capabilities: row.capabilities,
          supported_models: row.supported_models,
          rate_limits: row.rate_limits,
          default_parameters: row.default_parameters,
          pricing_info: row.pricing_info,
          created_at: iso(row.created_at),
          updated_at: iso(row.updated_at)
        )
      end

      # "Can this provider be used", answered WITHOUT answering "with what".
      # Every value here is a boolean, a count or a timestamp derived from the
      # credential rows; `encrypted_credentials`, `vault_path`,
      # `encryption_key_id` and `last_error` are all deliberately absent —
      # `last_error` because a provider's rejection body can echo the key it
      # rejected.
      def credential_status(row)
        creds = row.provider_credentials
        active = creds.select(&:is_active)
        {
          configured: creds.any?,
          active_count: active.size,
          any_expired: active.any? { |c| c.expires_at.present? && c.expires_at.past? },
          last_test_status: active.filter_map(&:last_test_status).first,
          last_test_at: iso(active.filter_map(&:last_test_at).max),
          last_used_at: iso(active.filter_map(&:last_used_at).max)
        }
      end

      def truthy?(value)
        value == true || value.to_s == "true"
      end

      def iso(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value
      end
    end
  end
end
