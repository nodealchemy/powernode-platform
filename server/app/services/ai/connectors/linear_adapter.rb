# frozen_string_literal: true

module Ai
  module Connectors
    # Native Linear issue-tracker client. Creates issues via the Linear GraphQL
    # `issueCreate` mutation at https://api.linear.app/graphql, authenticating with
    # the raw API key in the Authorization header (Linear's personal-API-key scheme).
    #
    # Config (TrackerConfig / SiteSetting, ENV fallback):
    #   ai_tracker_linear_api_key, ai_tracker_linear_team_id
    #
    # Returns { ok:, external_id: issue.id, url: issue.url } on success, and a
    # secret-free { ok: false, error: } on missing config, GraphQL errors, non-2xx,
    # or transport failure.
    class LinearAdapter < VendorWebhookAdapter
      ENDPOINT = "https://api.linear.app/graphql"

      MUTATION = <<~GRAPHQL
        mutation IssueCreate($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue { id identifier url }
          }
        }
      GRAPHQL

      # Linear priority scale: 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low.
      PRIORITY = { "critical" => 1, "error" => 2, "high" => 2, "warning" => 3, "info" => 4, "low" => 4 }.freeze

      def self.vendor_label = "Linear"
      def self.vendor_key = :linear

      def create_issue(title:, body:, severity: "warning", metadata: {})
        api_key = TrackerConfig.linear_api_key
        team_id = TrackerConfig.linear_team_id
        return failure("Linear tracker missing required config (api key / team id)") if api_key.blank? || team_id.blank?

        input = {
          teamId: team_id,
          title: title.to_s,
          description: body.to_s,
          priority: priority_for(severity)
        }
        response = post_json(
          ENDPOINT,
          headers: { "Authorization" => api_key },
          payload: { query: MUTATION, variables: { input: input } }
        )
        return failure("Linear returned HTTP #{response.status}") unless success?(response.status)

        parsed = parse(response.body)
        if parsed["errors"].present?
          return failure("Linear issueCreate failed: #{Array(parsed["errors"]).map { |e| e["message"] }.join("; ")}")
        end

        issue = parsed.dig("data", "issueCreate", "issue") || {}
        { ok: true, external_id: issue["id"], url: issue["url"] }
      rescue Faraday::Error => e
        failure("Linear request failed: #{e.class}")
      end

      # Linear is an issue tracker: surface errors as issues.
      def report_error(error:, severity: "error", context: {})
        create_issue(title: error.to_s, body: context_body(context), severity: severity, metadata: context)
      end

      private

      def priority_for(severity)
        PRIORITY.fetch(severity.to_s.downcase, 3)
      end

      def context_body(context)
        return "" if context.blank?

        JSON.pretty_generate(context)
      rescue StandardError
        context.to_s
      end
    end
  end
end
