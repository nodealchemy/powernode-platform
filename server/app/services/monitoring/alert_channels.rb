# frozen_string_literal: true

module Monitoring
  # Where the alert channels are configured, and the one place that knows the
  # key names (design E8, lead rulings 2026-09-10).
  #
  # THREE CREDENTIALS live in Security::SecretStore, platform-global
  # (account: nil) under SECRET_SCOPE. A Slack incoming-webhook URL is itself
  # the capability to post; the outbound webhook URL and its bearer token are
  # the same shape. They are write-only on the wire (the REST door answers
  # `configured: true|false`), no MCP verb reads or writes them, and no value
  # appears in a log line, an error message or an audit row. Messages raised
  # from here name the KEY, never the value.
  #
  # FOUR PLAIN SETTINGS are SiteSettings, absence-means-off: nothing is seeded,
  # and the operator surface creates a row on first write, always
  # is_public: false. A missing email means the email channel is off; a
  # missing min_severity_* means DEFAULT_MIN_SEVERITY.
  #
  # NO MASTER SWITCH. ALERTING_ENABLED was deleted: a channel is live if and
  # only if it is configured. A second switch is a redundant guard, and a
  # redundant guard corrupts every oracle that tries to prove the first.
  # SLACK_ALERT_CHANNEL was deleted too: an incoming webhook is bound to its
  # channel, and current Slack apps ignore the override.
  module AlertChannels
    CHANNELS = %w[slack email webhook].freeze

    SECRET_SCOPE = "platform.status.alert_channels"
    SLACK_WEBHOOK_URL = "slack_webhook_url"
    WEBHOOK_URL = "webhook_url"
    WEBHOOK_AUTH_TOKEN = "webhook_auth_token"
    SECRET_KEYS = [ SLACK_WEBHOOK_URL, WEBHOOK_URL, WEBHOOK_AUTH_TOKEN ].freeze
    URL_SECRET_KEYS = [ SLACK_WEBHOOK_URL, WEBHOOK_URL ].freeze

    SETTING_PREFIX = "platform.status.alert_channels."
    SETTING_NAMES = %w[email min_severity_slack min_severity_email min_severity_webhook].freeze

    # The floor each channel has always used, named rather than inlined. It
    # used to be `ENV["MIN_SEVERITY_SLACK"] || "warning"` and friends; the
    # values are unchanged. Not a new policy.
    DEFAULT_MIN_SEVERITY = { "slack" => :warning, "email" => :error, "webhook" => :critical }.freeze

    DESCRIPTIONS = {
      "email" => "Address that receives platform alert emails. Absent means the email channel is off.",
      "min_severity_slack" => "Lowest alert severity delivered to Slack. Absent means warning.",
      "min_severity_email" => "Lowest alert severity delivered by email. Absent means error.",
      "min_severity_webhook" => "Lowest alert severity delivered to the outbound webhook. Absent means critical."
    }.freeze

    class InvalidSetting < StandardError; end

    # The audit row's resource. AuditLog requires resource_type and resource_id,
    # and a platform-global credential has no row under the Vault backend, so
    # the KEY NAME is the id ("settings" for the plain-settings group). That
    # makes AuditLog.for_resource(AuditRef.name, "slack_webhook_url") one
    # credential's whole history. It never carries a value.
    AuditRef = Struct.new(:id)
    SETTINGS_AUDIT_ID = "settings"

    module_function

    def setting_key(name)
      "#{SETTING_PREFIX}#{name}"
    end

    # ---- credentials -------------------------------------------------------

    # Presence without the value. Raises Security::SecretStore::BackendUnavailable
    # when the store is selected but unreachable; callers decide how to fail
    # closed, and must not treat that as "not configured".
    def secret_configured?(key)
      read_secret(key).present?
    end

    # The ONLY method that returns a credential. Callers use it on the spot and
    # hand it to nothing but the HTTP client.
    def read_secret(key)
      assert_secret_key!(key)
      ::Security::SecretStore.read(account: nil, scope: SECRET_SCOPE, key: key)
    end

    # Validation without a write, so a caller can check a whole batch before
    # storing any of it. Returns the normalized value.
    def validate_secret!(key, value)
      assert_secret_key!(key)
      candidate = value.to_s.strip
      raise InvalidSetting, "#{key} is blank; clearing is its own action" if candidate.empty?
      raise InvalidSetting, "#{key} must be an https URL" if URL_SECRET_KEYS.include?(key) && !https_url?(candidate)

      candidate
    end

    # @return [:set, :replaced] so the caller can audit which one happened
    def write_secret!(key, value)
      candidate = validate_secret!(key, value)
      existed = secret_configured?(key)
      ::Security::SecretStore.write(account: nil, scope: SECRET_SCOPE, key: key, value: candidate)
      existed ? :replaced : :set
    end

    # @return [Boolean] whether there was a value to clear
    def clear_secret!(key)
      assert_secret_key!(key)
      existed = secret_configured?(key)
      ::Security::SecretStore.delete(account: nil, scope: SECRET_SCOPE, key: key)
      existed
    end

    # { "slack_webhook_url" => { configured: true }, ... } — never a value.
    def secrets_status
      SECRET_KEYS.index_with { |key| { configured: secret_configured?(key) } }
    end

    # ---- plain settings ----------------------------------------------------

    def email
      ::SiteSetting.get(setting_key("email")).to_s.strip.presence
    end

    def min_severity(channel)
      stored = ::SiteSetting.get(setting_key("min_severity_#{channel}")).to_s.strip
      severities.include?(stored) ? stored.to_sym : DEFAULT_MIN_SEVERITY.fetch(channel.to_s)
    end

    # Stored values only; nil means absent (the channel is off, or the floor is
    # the default).
    def settings
      SETTING_NAMES.index_with { |name| ::SiteSetting.get(setting_key(name)).to_s.strip.presence }
    end

    def defaults
      DEFAULT_MIN_SEVERITY.to_h { |channel, floor| [ "min_severity_#{channel}", floor.to_s ] }
    end

    def severities
      ::Monitoring::AlertingService::SEVERITY_LEVELS.keys.map(&:to_s)
    end

    # All-or-nothing: every value is validated before any row is written. A
    # blank value REMOVES the row (absence means off) rather than storing a
    # blank the model would reject.
    #
    # @return [Array<String>] the names whose stored value changed
    def update_settings!(attrs)
      normalized = attrs.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.strip }
      unknown = normalized.keys - SETTING_NAMES
      raise InvalidSetting, "unknown setting: #{unknown.join(', ')}" if unknown.any?

      normalized.each { |name, value| validate_setting!(name, value) unless value.empty? }

      ::SiteSetting.transaction do
        normalized.filter_map do |name, value|
          key = setting_key(name)
          before = ::SiteSetting.get(key).to_s.strip.presence
          if value.empty?
            ::SiteSetting.find_by(key: key)&.destroy!
          else
            ::SiteSetting.set(key, value, description: DESCRIPTIONS.fetch(name),
                                          setting_type: "string", is_public: false)
          end
          name if before != value.presence
        end
      end
    end

    def validate_setting!(name, value)
      if name == "email"
        raise InvalidSetting, "email is not a valid address" unless value.match?(URI::MailTo::EMAIL_REGEXP)
      elsif !severities.include?(value)
        raise InvalidSetting, "#{name} must be one of #{severities.join(', ')}"
      end
    end

    def https_url?(candidate)
      uri = URI.parse(candidate)
      uri.is_a?(URI::HTTPS) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def assert_secret_key!(key)
      raise InvalidSetting, "unknown secret key" unless SECRET_KEYS.include?(key.to_s)
    end
  end
end
