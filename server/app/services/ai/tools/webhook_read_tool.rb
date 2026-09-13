# frozen_string_literal: true

module Ai
  module Tools
    # OUTBOUND WEBHOOKS, READ-ONLY (audit remedy 18).
    #
    # `WebhookEndpoint` had zero MCP verbs (`provision_disk_image_webhook` is
    # disk-image CI, a different thing). An agent diagnosing "the integration
    # stopped receiving events" could not see whether the endpoint was circuit-
    # broken or whether its deliveries were failing.
    #
    # ── FOUR SECRET-BEARING COLUMNS, ALL WITHHELD ───────────────────────────
    #
    # `webhook_endpoints` carries FOUR fields this tool must never emit, and
    # two of them are PLAINTEXT string columns, not `encrypts`-backed:
    #
    #   secret_key        the shared secret (plaintext column)
    #   signature_secret  the HMAC signing secret (plaintext column)
    #   custom_headers    caller-supplied request headers — routinely hold an
    #   headers           Authorization / bearer token
    #
    # This is not a theoretical risk here. The REST twin already leaks one:
    # `WebhooksController#detailed_webhook_data` returns `secret_key` verbatim
    # in its `show` payload (webhooks_controller.rb:423) even though the model
    # ships a `masked_secret` helper. That is an existing operator-only surface
    # and out of this increment's partition — but it is exactly why this tool
    # emits neither the value NOR the mask, only the boolean `secret_configured`.
    # A mask still discloses length and shape.
    #
    # Deliveries carry a fifth: `WebhookDelivery#request_headers` holds the
    # outbound signature header and any custom auth headers, and `response_body`
    # is raw remote output. Neither is returned; see #serialize_delivery.
    #
    # Every serializer below is an ALLOW-LIST, so a column added to either table
    # tomorrow does not appear by default.
    class WebhookReadTool < BaseTool
      REQUIRED_PERMISSION = "webhook.read"

      ACTION_PERMISSIONS = {
        "list_webhooks" => "webhook.read",
        "get_webhook" => "webhook.read",
        "list_webhook_deliveries" => "webhook.read"
      }.freeze

      declare_action "list_webhooks", mutating: false
      declare_action "get_webhook", mutating: false
      declare_action "list_webhook_deliveries", mutating: false

      def self.definition
        {
          name: "webhook_read",
          description: "Read-only view of the account's outbound webhook endpoints and their recent " \
                       "delivery attempts. Never returns signing secrets, shared secrets or request headers.",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "list_webhooks" => {
            description: "List this account's outbound webhook endpoints: URL, subscribed event types, " \
                         "active flag, circuit-breaker state and success/failure counts. Secrets are " \
                         "never returned — `secret_configured` is a boolean. Requires webhook.read.",
            parameters: {
              active_only: { type: "boolean", required: false, description: "Only endpoints with is_active true" },
              event_type: { type: "string", required: false, description: "Only endpoints subscribed to this event type" },
              **PAGINATION_PARAMETERS
            }
          },
          "get_webhook" => {
            description: "One endpoint with its delivery configuration (retries, backoff, timeout, rate " \
                         "limit) and circuit-breaker state. Signing secrets, shared secrets and custom " \
                         "headers are never returned, not even masked. Requires webhook.read.",
            parameters: {
              id: { type: "string", required: true, description: "Webhook endpoint id (must be in this account)" }
            }
          },
          "list_webhook_deliveries" => {
            description: "Recent delivery attempts, newest first: status, HTTP response code, latency, " \
                         "attempt number and error message. Request headers (which carry the signature) " \
                         "and raw response bodies are never returned. Requires webhook.read.",
            parameters: {
              webhook_id: { type: "string", required: false, description: "Filter to one endpoint" },
              status: { type: "string", required: false, description: "Filter by delivery status" },
              failed_only: { type: "boolean", required: false, description: "Only attempts that did not succeed" },
              **PAGINATION_PARAMETERS
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s
        return error_result("permission denied: #{required_perm_for(action)} required") unless action_permitted?(action)

        case action
        when "list_webhooks"           then list_webhooks(params)
        when "get_webhook"             then get_webhook(params)
        when "list_webhook_deliveries" then list_webhook_deliveries(params)
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

      def endpoints
        ::WebhookEndpoint.where(account_id: account.id)
      end

      def list_webhooks(params)
        scope = endpoints
        scope = scope.where(is_active: true) if truthy?(params[:active_only])
        if params[:event_type].present?
          # event_types is a jsonb array; containment keeps the filter in the
          # database rather than loading every endpoint to scan in Ruby.
          scope = scope.where("event_types @> ?", [ params[:event_type].to_s ].to_json)
        end

        paginated_result(:webhooks, scope, params, sort: :id, direction: :asc) { |row| serialize_webhook(row) }
      end

      def get_webhook(params)
        row = endpoints.find_by(id: params[:id].to_s)
        return error_result("webhook not found in this account") unless row

        success_result(webhook: serialize_webhook(row, detail: true))
      end

      def list_webhook_deliveries(params)
        scope = ::WebhookDelivery.where(webhook_endpoint_id: endpoints.select(:id))
        scope = scope.where(webhook_endpoint_id: params[:webhook_id].to_s) if params[:webhook_id].present?
        scope = scope.where(status: params[:status].to_s) if params[:status].present?
        scope = scope.where.not(status: "success") if truthy?(params[:failed_only])

        paginated_result(:deliveries, scope, params, sort: :id, direction: :desc) { |row| serialize_delivery(row) }
      end

      # ALLOW-LIST. `secret_key`, `signature_secret`, `custom_headers` and
      # `headers` are absent by construction — and `secret_configured` is a
      # BOOLEAN rather than a mask, because a mask still discloses length.
      def serialize_webhook(row, detail: false)
        payload = {
          id: row.id,
          url: row.url,
          description: row.description,
          event_types: row.event_types,
          is_active: row.is_active,
          status: row.status,
          secret_configured: row.secret_key.present?,
          signature_configured: row.signature_secret.present?,
          success_count: row.success_count,
          failure_count: row.failure_count,
          consecutive_failures: row.consecutive_failures,
          circuit_broken: row.circuit_broken_at.present?,
          circuit_cooldown_until: iso(row.circuit_cooldown_until),
          last_delivery_at: iso(row.last_delivery_at)
        }
        return payload unless detail

        payload.merge(
          content_type: row.content_type,
          payload_detail_level: row.payload_detail_level,
          tier: row.tier,
          timeout_seconds: row.timeout_seconds,
          max_retries: row.max_retries,
          retry_limit: row.retry_limit,
          retry_backoff: row.retry_backoff,
          circuit_break_threshold: row.circuit_break_threshold,
          daily_limit: row.daily_limit,
          daily_count: row.daily_count,
          created_at: iso(row.created_at),
          updated_at: iso(row.updated_at)
        )
      end

      # `request_headers` carries the outbound signature header and any custom
      # auth headers; `response_headers` can echo a remote's own credentials;
      # `response_body` is unbounded raw remote output. All three are withheld.
      # What is left — status, code, latency, attempt, error message — is what
      # an operator actually diagnoses with.
      def serialize_delivery(row)
        {
          id: row.id,
          webhook_endpoint_id: row.webhook_endpoint_id,
          status: row.status,
          response_status: row.response_status,
          response_time_ms: row.response_time_ms,
          attempt_number: row.attempt_number,
          attempted_at: iso(row.attempted_at),
          next_retry_at: iso(row.next_retry_at),
          error_message: row.error_message,
          created_at: iso(row.created_at)
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
