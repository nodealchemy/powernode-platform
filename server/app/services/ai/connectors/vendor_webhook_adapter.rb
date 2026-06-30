# frozen_string_literal: true

module Ai
  module Connectors
    # Shared HTTP plumbing for the NATIVE vendor tracker adapters (Linear / Jira /
    # Sentry). Provides a Faraday JSON client in the same house style as
    # GenericWebhookTrackerAdapter, response parsing, a 2xx check, and graceful,
    # secret-free failure helpers.
    #
    # Contract for subclasses:
    #   - resolve their own config (endpoint + auth) lazily from TrackerConfig,
    #   - implement #create_issue / #report_error using the helpers below,
    #   - return { ok:, external_id:, url: } on success and { ok: false, error: }
    #     on any failure (missing config, non-2xx, transport error) — NEVER raise
    #     into the best-effort TrackerBridge.
    #
    # SECRET SAFETY: api keys, tokens and DSNs are NEVER placed in returned errors
    # or logs. Helpers here only surface HTTP status / exception class names.
    class VendorWebhookAdapter
      DEFAULT_TIMEOUT = 5

      def initialize(timeout: DEFAULT_TIMEOUT)
        @timeout = timeout
      end

      def name
        self.class.vendor_key
      end

      # Default no-ops keep the registry contract satisfied for any subclass that
      # only implements one direction; concrete vendors override as appropriate.
      def create_issue(title:, body:, severity: "warning", metadata: {})
        failure("#{self.class.vendor_label} create_issue is not implemented")
      end

      def report_error(error:, severity: "error", context: {})
        failure("#{self.class.vendor_label} report_error is not implemented")
      end

      class << self
        def vendor_label
          raise NotImplementedError, "#{name} must define .vendor_label"
        end

        def vendor_key
          raise NotImplementedError, "#{name} must define .vendor_key"
        end
      end

      private

      # POST +payload+ (Hash) as JSON to +url+ with +headers+ merged over a
      # JSON content-type. Returns the raw Faraday::Response.
      def post_json(url, payload:, headers: {})
        connection(url).post do |req|
          { "Content-Type" => "application/json" }.merge(headers).each do |key, value|
            req.headers[key.to_s] = value.to_s
          end
          req.body = payload.to_json
        end
      end

      def connection(url)
        Faraday.new(url: url) do |conn|
          conn.options.timeout = @timeout
          conn.options.open_timeout = @timeout
          conn.adapter Faraday.default_adapter
        end
      end

      def success?(status)
        status.to_i.between?(200, 299)
      end

      def parse(raw)
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end

      # Graceful, secret-free failure result. Callers MUST NOT interpolate any
      # token / key / DSN into +message+.
      def failure(message)
        { ok: false, error: message }
      end
    end
  end
end
