# frozen_string_literal: true

module Ai
  module Connectors
    # Vendor-agnostic reference adapter: it POSTs the issue/error payload as JSON
    # to a configured webhook URL WITHOUT any vendor-specific auth. Useful as a
    # generic destination (proxy, Zapier-style hook, custom intake). The named
    # vendors (Linear/Jira/Sentry) are native API clients and do NOT route through
    # this adapter.
    #
    # Config is taken from the explicit constructor args when given, otherwise
    # resolved lazily from Ai::Connectors::TrackerConfig at call time (so a
    # single registered instance picks up DB-driven config).
    class GenericWebhookTrackerAdapter
      DEFAULT_TIMEOUT = 5

      def initialize(url: nil, headers: nil, name: :generic_webhook, timeout: DEFAULT_TIMEOUT)
        @url = url
        @headers = headers
        @name = name.to_sym
        @timeout = timeout
      end

      attr_reader :name

      def create_issue(title:, body:, severity: "warning", metadata: {})
        deliver(event: "issue", payload: { title: title, body: body, severity: severity, metadata: metadata })
      end

      def report_error(error:, severity: "error", context: {})
        deliver(event: "error", payload: { error: error, severity: severity, context: context })
      end

      private

      def deliver(event:, payload:)
        target = endpoint
        raise ArgumentError, "no webhook URL configured for tracker #{name.inspect}" if target.blank?

        response = post_json(target, payload.merge(event: event, source: "powernode", connector: name.to_s))
        body = parse(response.body)

        {
          ok: success?(response.status),
          status: response.status,
          external_id: body["id"] || body["key"] || body["external_id"],
          url: body["url"] || body["html_url"] || body["self"]
        }
      rescue Faraday::Error => e
        { ok: false, error: e.message }
      end

      def post_json(target, hash)
        connection(target).post do |req|
          request_headers.each { |key, value| req.headers[key.to_s] = value.to_s }
          req.body = hash.to_json
        end
      end

      def connection(target)
        Faraday.new(url: target) do |conn|
          conn.options.timeout = @timeout
          conn.options.open_timeout = @timeout
          conn.adapter Faraday.default_adapter
        end
      end

      def request_headers
        { "Content-Type" => "application/json" }.merge(@headers || Ai::Connectors::TrackerConfig.headers)
      end

      def endpoint
        @url || Ai::Connectors::TrackerConfig.endpoint
      end

      def success?(status)
        status.to_i.between?(200, 299)
      end

      def parse(raw)
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
