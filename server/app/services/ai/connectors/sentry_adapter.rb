# frozen_string_literal: true

module Ai
  module Connectors
    # Sentry error-tracker scaffolding. Full Sentry client (DSN/store or events
    # API auth) is the documented G8 follow-up; until then this delegates to the
    # generic webhook proxy when one is configured.
    class SentryAdapter < VendorWebhookAdapter
      def self.vendor_label
        "Sentry"
      end

      def self.vendor_key
        :sentry
      end
    end
  end
end
