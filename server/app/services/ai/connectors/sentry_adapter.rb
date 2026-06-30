# frozen_string_literal: true

require "securerandom"

module Ai
  module Connectors
    # Native Sentry error-tracker client. Sentry has no first-class "create issue"
    # API — issues are derived server-side from INGESTED EVENTS — so the primary
    # operation is #report_error, which captures an event to the Sentry store
    # endpoint derived from the configured DSN. #create_issue is a thin convenience
    # that maps a title/body to an event capture.
    #
    # Config (TrackerConfig / SiteSetting, ENV fallback):
    #   ai_tracker_sentry_dsn  e.g. https://<public_key>@<host>/<project_id>
    #
    # The store endpoint is {scheme}://{host}/api/{project_id}/store/ and auth is
    # the X-Sentry-Auth header carrying the DSN's PUBLIC key (not a secret).
    #
    # SIMPLIFICATION: a minimal event envelope (event_id / timestamp / level /
    # message / logger + context as extra) is sent. external_id is the returned
    # event id; url is left nil because a browseable issue URL is not derivable
    # from an event id alone (it needs the org/project slug, which the DSN omits).
    class SentryAdapter < VendorWebhookAdapter
      SENTRY_VERSION = "7"
      CLIENT = "powernode/1.0"

      # Sentry levels: fatal, error, warning, info, debug.
      LEVEL = {
        "critical" => "fatal", "fatal" => "fatal", "error" => "error",
        "warning" => "warning", "warn" => "warning", "info" => "info", "debug" => "debug"
      }.freeze

      def self.vendor_label = "Sentry"
      def self.vendor_key = :sentry

      def report_error(error:, severity: "error", context: {})
        dsn = parse_dsn(TrackerConfig.sentry_dsn)
        return failure("Sentry tracker missing/invalid DSN config") if dsn.nil?

        event_id = SecureRandom.hex(16)
        payload = {
          event_id: event_id,
          timestamp: Time.now.utc.iso8601,
          platform: "ruby",
          logger: "powernode",
          level: level_for(severity),
          message: error.to_s,
          extra: (context || {})
        }
        response = post_json(
          dsn[:store_url],
          headers: { "X-Sentry-Auth" => sentry_auth_header(dsn[:public_key]) },
          payload: payload
        )
        return failure("Sentry returned HTTP #{response.status}") unless success?(response.status)

        returned_id = parse(response.body)["id"]
        { ok: true, external_id: returned_id.presence || event_id, url: nil }
      rescue Faraday::Error => e
        failure("Sentry request failed: #{e.class}")
      end

      # No native create-issue: capture the title/body as an event.
      def create_issue(title:, body:, severity: "warning", metadata: {})
        message = [ title, body ].map(&:to_s).reject(&:blank?).join("\n\n")
        report_error(error: message, severity: severity, context: metadata || {})
      end

      private

      def level_for(severity)
        LEVEL.fetch(severity.to_s.downcase, "error")
      end

      def sentry_auth_header(public_key)
        "Sentry sentry_version=#{SENTRY_VERSION}, sentry_client=#{CLIENT}, sentry_key=#{public_key}"
      end

      # Parse a Sentry DSN into the store endpoint + public key. Returns nil when
      # the DSN is blank or unparseable. NEVER logs the DSN.
      def parse_dsn(dsn)
        return nil if dsn.blank?

        uri = URI.parse(dsn)
        public_key = uri.user
        project_id = uri.path.to_s.delete_prefix("/")
        return nil if public_key.blank? || project_id.blank? || uri.host.blank?

        host = uri.host
        host = "#{host}:#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)
        { public_key: public_key, store_url: "#{uri.scheme}://#{host}/api/#{project_id}/store/" }
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
