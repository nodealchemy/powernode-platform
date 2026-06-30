# frozen_string_literal: true

require "base64"

module Ai
  module Connectors
    # Native Jira (Cloud) issue-tracker client. Creates issues via the REST v3
    # endpoint POST {base_url}/rest/api/3/issue using Basic auth (account email +
    # API token). The description is sent as Atlassian Document Format (ADF), which
    # the v3 API requires.
    #
    # Config (TrackerConfig / SiteSetting, ENV fallback):
    #   ai_tracker_jira_base_url, ai_tracker_jira_email, ai_tracker_jira_api_token,
    #   ai_tracker_jira_project_key, ai_tracker_jira_issue_type (default "Task")
    #
    # SIMPLIFICATION: only the minimal required fields (project / summary /
    # description / issuetype) are sent. Severity is not mapped to a Jira priority
    # because the priority field's allowed values are project-scheme dependent and
    # would risk a 400 on arbitrary instances; severity is preserved in the
    # description instead. Returns { ok:, external_id: key, url: ".../browse/key" }.
    class JiraAdapter < VendorWebhookAdapter
      def self.vendor_label = "Jira"
      def self.vendor_key = :jira

      def create_issue(title:, body:, severity: "warning", metadata: {})
        base_url = TrackerConfig.jira_base_url
        email = TrackerConfig.jira_email
        token = TrackerConfig.jira_api_token
        project_key = TrackerConfig.jira_project_key
        if base_url.blank? || email.blank? || token.blank? || project_key.blank?
          return failure("Jira tracker missing required config (base url / email / api token / project key)")
        end

        fields = {
          project: { key: project_key },
          summary: title.to_s,
          description: adf(body.to_s.presence || "(no description provided)"),
          issuetype: { name: TrackerConfig.jira_issue_type }
        }
        response = post_json(
          "#{base_url}/rest/api/3/issue",
          headers: { "Authorization" => basic_auth(email, token), "Accept" => "application/json" },
          payload: { fields: fields }
        )
        return failure("Jira returned HTTP #{response.status}") unless success?(response.status)

        key = parse(response.body)["key"]
        { ok: true, external_id: key, url: key.present? ? "#{base_url}/browse/#{key}" : nil }
      rescue Faraday::Error => e
        failure("Jira request failed: #{e.class}")
      end

      def report_error(error:, severity: "error", context: {})
        create_issue(title: error.to_s, body: context_body(context), severity: severity, metadata: context)
      end

      private

      def basic_auth(email, token)
        "Basic #{Base64.strict_encode64("#{email}:#{token}")}"
      end

      # Minimal valid ADF document wrapping +text+ in a single paragraph.
      def adf(text)
        {
          type: "doc",
          version: 1,
          content: [
            { type: "paragraph", content: [ { type: "text", text: text.to_s } ] }
          ]
        }
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
