# frozen_string_literal: true

module Ai
  module Connectors
    # Linear issue-tracker scaffolding. Full Linear GraphQL API client (OAuth /
    # API-key auth + issueCreate mutation) is the documented G8 follow-up; until
    # then this delegates to the generic webhook proxy when one is configured.
    class LinearAdapter < VendorWebhookAdapter
      def self.vendor_label
        "Linear"
      end

      def self.vendor_key
        :linear
      end
    end
  end
end
