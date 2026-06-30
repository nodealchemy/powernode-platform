# frozen_string_literal: true

module Ai
  module Connectors
    # Jira issue-tracker scaffolding. Full Jira REST API client (basic/OAuth auth +
    # POST /rest/api/3/issue, project/issuetype mapping) is the documented G8
    # follow-up; until then this delegates to the generic webhook proxy when one is
    # configured.
    class JiraAdapter < VendorWebhookAdapter
      def self.vendor_label
        "Jira"
      end

      def self.vendor_key
        :jira
      end
    end
  end
end
