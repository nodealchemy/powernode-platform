# frozen_string_literal: true

# Host-header allow policy backed by AdminSetting.reverse_proxy_url_config[:trusted_hosts].
# Registered as a config.hosts lambda in development; extracted from the inline
# lambda so it is testable through ActionDispatch::HostAuthorization.
#
# Patterns: exact host (case-insensitive) or "*.example.com" (matches example.com
# and any subdomain). Ports on either side are ignored. localhost/127.0.0.1 always pass.
class TrustedHostPolicy
  ALWAYS_ALLOWED = %w[localhost 127.0.0.1].freeze

  class << self
    def allowed?(host)
      host_name = host.to_s.split(":").first.to_s.downcase
      return true if ALWAYS_ALLOWED.include?(host_name)
      return false unless defined?(AdminSetting) && ActiveRecord::Base.connection.table_exists?("admin_settings")

      config = AdminSetting.reverse_proxy_url_config
      return false unless config.is_a?(Hash) && config[:trusted_hosts].is_a?(Array)

      config[:trusted_hosts].any? { |pattern| matches?(host_name, pattern) }
    rescue StandardError
      false
    end

    private

    def matches?(host_name, pattern)
      return false if pattern.blank?

      pattern_host = pattern.to_s.split(":").first.to_s.downcase
      if pattern_host.start_with?("*.")
        domain = pattern_host[2..]
        host_name.end_with?(".#{domain}") || host_name == domain
      else
        host_name == pattern_host
      end
    end
  end
end
