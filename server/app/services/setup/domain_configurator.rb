# frozen_string_literal: true

module Setup
  # Applies the setup wizard's domain step: one primary domain plus any number of
  # additional domains (exact hosts or "*.example.com" wildcards).
  #
  #   * primary          -> SiteSetting "domain" (seed data / bootstrap URL)
  #   * all domains      -> AdminSetting reverse_proxy_url_config[:trusted_hosts]
  #                         (dev HostAuthorization via TrustedHostPolicy; production
  #                         Traefik host rules via Core::IngressConfigWriter)
  #   * all domains      -> AdminSetting "cors_allowed_origins" (merged, never wiped).
  #                         Exact hosts add https://<d> (plus http://<d>:3001 in
  #                         development). Wildcards need no entry here: via trusted_hosts
  #                         CorsConfigurationService derives a regex origin for them, which
  #                         is why wildcards are validated strictly (WildcardHostPattern).
  #
  # Idempotent. Ownership: only entries the wizard itself ADDED (absent before its
  # write) are tracked in SiteSetting "wizard_owned_entries" and removed on a later
  # re-run; entries the operator already had are never removed.
  class DomainConfigurator
    class InvalidDomain < StandardError; end

    LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/i
    HOSTNAME = /\A#{LABEL}(?:\.#{LABEL})*\z/
    DEV_FRONTEND_PORT = 3001

    RESERVED = %w[localhost 127.0.0.1 ::1].freeze

    def self.call(primary:, additional: [], user: nil, account: nil, ip_address: nil, user_agent: nil)
      new(primary, additional, user: user, account: account, ip_address: ip_address, user_agent: user_agent).call
    end

    # Accepts an Array or a newline/comma/space separated String.
    def self.split(value)
      list = value.is_a?(Array) ? value : value.to_s.split(/[\n,]+/)
      list.map { |d| d.to_s.strip }.reject(&:blank?)
    end

    def initialize(primary, additional, user: nil, account: nil, ip_address: nil, user_agent: nil)
      @user = user
      @account = account
      @ip_address = ip_address
      @user_agent = user_agent
      @primary = primary.to_s.strip.downcase
      @additional = self.class.split(additional).map(&:downcase)
    end

    def call
      validate!
      domains = ([ @primary ] + @additional).uniq
      audit = nil

      ActiveRecord::Base.transaction do
        SiteSetting.set("domain", @primary, description: "Public domain for this instance", is_public: true)
        trusted = apply_list(current_trusted_hosts, domains, "trusted_hosts") do |merged|
          AdminSetting.update_reverse_proxy_url_config(trusted_hosts: merged)
        end
        cors = apply_list(current_cors_origins, origins_for(domains), "cors_origins") do |merged|
          AdminSetting.set("cors_allowed_origins", merged)
        end
        SiteSetting.set("wizard_owned_entries", @owned, description: "Config entries added by the setup wizard", setting_type: "json")
        audit = { domains: domains, trusted_hosts_added: trusted[:added], trusted_hosts_removed: trusted[:removed],
                  cors_origins_added: cors[:added], cors_origins_removed: cors[:removed] }
      end
      record_audit(audit)
      domains
    end

    private

    def validate!
      raise InvalidDomain, "Domain is required" if @primary.blank?
      raise InvalidDomain, "Primary domain cannot be a wildcard" if @primary.include?("*")

      ([ @primary ] + @additional).each do |d|
        raise InvalidDomain, "'#{d}' is reserved and always allowed" if RESERVED.include?(d)

        if d.include?("*")
          raise InvalidDomain, "Wildcard '#{d}' is too broad or invalid (use *.example.com)" unless WildcardHostPattern.valid?(d)
        else
          raise InvalidDomain, "Invalid domain '#{d}'" unless d.length <= 253 && d.match?(HOSTNAME)
        end
      end
    end

    def owned
      @owned ||= begin
        stored = SiteSetting.get("wizard_owned_entries")
        stored = {} unless stored.is_a?(Hash)
        { "trusted_hosts" => Array(stored["trusted_hosts"]), "cors_origins" => Array(stored["cors_origins"]) }
      end
    end

    # Removes previously wizard-added entries no longer desired, adds desired ones, and
    # records as owned only what the wizard itself added. Returns {added:, removed:}.
    def apply_list(current, desired, key)
      prev_owned = owned[key] - RESERVED
      removed = (prev_owned - desired) & current
      kept = current - removed
      added = desired - kept
      yield (kept | desired)
      owned[key] = ((prev_owned & desired) | added) - RESERVED
      { added: added, removed: removed }
    end

    def current_trusted_hosts
      Array(AdminSetting.reverse_proxy_url_config[:trusted_hosts])
    end

    def current_cors_origins
      setting = AdminSetting.find_by(key: "cors_allowed_origins")
      setting&.value.present? ? CorsConfigurationService.send(:parse_cors_origins, setting.value) : []
    end

    def record_audit(details)
      return unless @account && defined?(AuditLog)

      # "admin_settings_update" is the registered action; metadata.change names the source.
      AuditLog.log_action(
        action: "admin_settings_update", resource: AdminSetting.find_by!(key: "reverse_proxy_url_config"),
        user: @user, account: @account, ip_address: @ip_address, user_agent: @user_agent,
        metadata: details.deep_stringify_keys.merge("change" => "setup.domains_configured")
      )
    rescue StandardError => e
      Rails.logger.error("[Setup::DomainConfigurator] audit log failed: #{e.class}")
    end

    def origins_for(domains)
      list = domains.reject { |d| d.include?("*") }.map { |d| "https://#{d}" }
      list += domains.reject { |d| d.include?("*") }.map { |d| "http://#{d}:#{DEV_FRONTEND_PORT}" } if Rails.env.development?
      list
    end
  end
end
