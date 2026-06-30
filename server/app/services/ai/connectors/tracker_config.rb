# frozen_string_literal: true

module Ai
  module Connectors
    # Resolves outbound-tracker configuration from SiteSetting (DB-driven), with
    # ENV fallbacks. NO migration required — config lives in existing SiteSetting
    # rows. Default (no rows / disabled) => #enabled? is false and nothing is
    # forwarded, so the internal report_issue / escalate paths are unchanged.
    #
    # Secrets (api keys, tokens, DSNs) are READ-ONLY from SiteSetting/ENV — never
    # persisted in code and never logged.
    #
    # Generic keys:
    #   ai_tracker_enabled         (boolean) master opt-in switch
    #   ai_tracker_adapter         (string)  registered adapter name (default "generic_webhook")
    #   ai_tracker_webhook_url     (string)  destination/proxy URL (ENV: AI_TRACKER_WEBHOOK_URL)
    #   ai_tracker_webhook_headers (json)    extra request headers
    #
    # Per-vendor keys (each also resolvable from the upcased ENV name):
    #   Linear:  ai_tracker_linear_api_key, ai_tracker_linear_team_id
    #   Jira:    ai_tracker_jira_base_url, ai_tracker_jira_email,
    #            ai_tracker_jira_api_token, ai_tracker_jira_project_key,
    #            ai_tracker_jira_issue_type (default "Task")
    #   Sentry:  ai_tracker_sentry_dsn
    module TrackerConfig
      DEFAULT_JIRA_ISSUE_TYPE = "Task"

      class << self
        def enabled?
          return false unless setting_bool("ai_tracker_enabled")
          return false if adapter_name.blank?

          configured_for?(adapter_name)
        end

        # True when the named adapter has the config it needs to actually deliver.
        # Adapter-aware so a vendor adapter (no webhook URL) can still be enabled.
        def configured_for?(name)
          case name.to_sym
          when :linear
            linear_api_key.present? && linear_team_id.present?
          when :jira
            jira_base_url.present? && jira_email.present? &&
              jira_api_token.present? && jira_project_key.present?
          when :sentry
            sentry_dsn.present?
          else
            # generic_webhook + any custom/extension adapter: webhook-style check.
            endpoint.present?
          end
        end

        def adapter_name
          (raw_adapter || "generic_webhook").to_sym
        end

        def endpoint
          resolve("ai_tracker_webhook_url")
        end

        def headers
          value = SiteSetting.get("ai_tracker_webhook_headers")
          value.is_a?(Hash) ? value : {}
        rescue StandardError
          {}
        end

        # --- Linear ---------------------------------------------------------
        def linear_api_key
          resolve("ai_tracker_linear_api_key")
        end

        def linear_team_id
          resolve("ai_tracker_linear_team_id")
        end

        # --- Jira -----------------------------------------------------------
        def jira_base_url
          resolve("ai_tracker_jira_base_url")&.chomp("/")
        end

        def jira_email
          resolve("ai_tracker_jira_email")
        end

        def jira_api_token
          resolve("ai_tracker_jira_api_token")
        end

        def jira_project_key
          resolve("ai_tracker_jira_project_key")
        end

        def jira_issue_type
          resolve("ai_tracker_jira_issue_type").presence || DEFAULT_JIRA_ISSUE_TYPE
        end

        # --- Sentry ---------------------------------------------------------
        def sentry_dsn
          resolve("ai_tracker_sentry_dsn")
        end

        private

        def raw_adapter
          resolve("ai_tracker_adapter")
        end

        # SiteSetting (string) first, then the upcased ENV name as fallback.
        def resolve(key)
          str(key) || env(key.upcase)
        end

        def str(key)
          value = SiteSetting.get(key)
          value.is_a?(String) ? value.presence : nil
        rescue StandardError
          nil
        end

        def env(key)
          ENV[key].presence
        end

        def setting_bool(key)
          SiteSetting.get(key) == true
        rescue StandardError
          false
        end
      end
    end
  end
end
