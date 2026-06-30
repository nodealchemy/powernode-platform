# frozen_string_literal: true

module Ai
  module Connectors
    # Resolves outbound-tracker configuration from SiteSetting (DB-driven), with
    # ENV fallbacks. NO migration required — config lives in existing SiteSetting
    # rows. Default (no rows / disabled) => #enabled? is false and nothing is
    # forwarded, so the internal report_issue / escalate paths are unchanged.
    #
    # Keys:
    #   ai_tracker_enabled        (boolean) master opt-in switch
    #   ai_tracker_adapter        (string)  registered adapter name (default "generic_webhook")
    #   ai_tracker_webhook_url    (string)  destination/proxy URL (ENV: AI_TRACKER_WEBHOOK_URL)
    #   ai_tracker_webhook_headers(json)    extra request headers
    module TrackerConfig
      class << self
        def enabled?
          setting_bool("ai_tracker_enabled") && adapter_name.present? && endpoint.present?
        end

        def adapter_name
          (raw_adapter || "generic_webhook").to_sym
        end

        def endpoint
          str("ai_tracker_webhook_url") || env("AI_TRACKER_WEBHOOK_URL")
        end

        def headers
          value = SiteSetting.get("ai_tracker_webhook_headers")
          value.is_a?(Hash) ? value : {}
        rescue StandardError
          {}
        end

        private

        def raw_adapter
          str("ai_tracker_adapter") || env("AI_TRACKER_ADAPTER")
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
