# frozen_string_literal: true

module Setup
  # Applies the setup wizard's domain step: one primary domain plus any number of
  # additional domains (exact hosts or "*.example.com" wildcards).
  #
  #   * primary          -> SiteSetting "domain" (seed data / bootstrap URL)
  #   * all domains      -> AdminSetting reverse_proxy_url_config[:trusted_hosts]
  #                         (dev HostAuthorization via TrustedHostPolicy; production
  #                         Traefik host rules via Core::IngressConfigWriter)
  #   * non-wildcard     -> AdminSetting "cors_allowed_origins" (merged, never wiped)
  #
  # Idempotent. Entries the wizard wrote previously (tracked in SiteSetting
  # "wizard_domains") are replaced on re-run; operator-added entries are kept.
  class DomainConfigurator
    class InvalidDomain < StandardError; end

    LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/i
    HOSTNAME = /\A#{LABEL}(?:\.#{LABEL})*\z/
    DEV_FRONTEND_PORT = 3001

    def self.call(primary:, additional: [])
      new(primary, additional).call
    end

    # Accepts an Array or a newline/comma/space separated String.
    def self.split(value)
      list = value.is_a?(Array) ? value : value.to_s.split(/[\n,]+/)
      list.map { |d| d.to_s.strip }.reject(&:blank?)
    end

    def initialize(primary, additional)
      @primary = primary.to_s.strip.downcase
      @additional = self.class.split(additional).map(&:downcase)
    end

    def call
      validate!
      domains = ([ @primary ] + @additional).uniq

      ActiveRecord::Base.transaction do
        SiteSetting.set("domain", @primary, description: "Public domain for this instance", is_public: true)
        write_trusted_hosts(domains)
        write_cors_origins(domains)
        SiteSetting.set("wizard_domains", domains, description: "Domains configured by the setup wizard", setting_type: "json")
      end
      domains
    end

    private

    def validate!
      raise InvalidDomain, "Domain is required" if @primary.blank?
      raise InvalidDomain, "Primary domain cannot be a wildcard" if @primary.include?("*")

      ([ @primary ] + @additional).each do |d|
        host = d.delete_prefix("*.")
        raise InvalidDomain, "Invalid domain '#{d}'" unless host.length <= 253 && host.match?(HOSTNAME) && (d == host || d.start_with?("*."))
      end
    end

    def previous
      Array(SiteSetting.get("wizard_domains"))
    end

    def write_trusted_hosts(domains)
      current = Array(AdminSetting.reverse_proxy_url_config[:trusted_hosts])
      merged = (current - previous) | domains
      AdminSetting.update_reverse_proxy_url_config(trusted_hosts: merged)
    end

    def write_cors_origins(domains)
      setting = AdminSetting.find_by(key: "cors_allowed_origins")
      current = setting&.value.present? ? CorsConfigurationService.send(:parse_cors_origins, setting.value) : []
      merged = (current - origins_for(previous)) | origins_for(domains)
      AdminSetting.set("cors_allowed_origins", merged)
    end

    def origins_for(domains)
      list = domains.reject { |d| d.include?("*") }.map { |d| "https://#{d}" }
      list += domains.reject { |d| d.include?("*") }.map { |d| "http://#{d}:#{DEV_FRONTEND_PORT}" } if Rails.env.development?
      list
    end
  end
end
