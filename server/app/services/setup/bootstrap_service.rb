# frozen_string_literal: true

module Setup
  # First-boot announcer: when no administrator exists yet, mint a one-time
  # bootstrap token and print the setup URL to the service console (visible via
  # `journalctl -u powernode-backend@default`). Invoked once at boot from
  # config/initializers/setup_bootstrap.rb — under preload_app! that runs in the
  # puma master, so the URL is logged exactly once, not once per worker.
  class BootstrapService
    class << self
      # @return [Boolean] true if a setup URL was announced
      def announce!
        return false unless needs_bootstrap?

        # Regenerate every boot while there are zero users, so the most recently
        # printed URL always works and stale tokens die on restart.
        url = setup_url(BootstrapToken.generate!)

        Rails.logger.info("[setup] No administrator exists yet — first-run setup required.")
        Rails.logger.info("[setup] Open this one-time URL to create the first admin:")
        Rails.logger.info("[setup]   #{url}")
        true
      end

      # @return [Boolean] zero users => bootstrap needed. Swallows DB errors so a
      #   not-yet-migrated database never blocks boot.
      def needs_bootstrap?
        !User.exists?
      rescue ActiveRecord::ActiveRecordError
        false
      end

      def setup_url(raw_token)
        "#{base_url}/setup?token=#{raw_token}"
      end

      private

      def base_url
        host = configured_host
        scheme = host.start_with?("localhost", "127.0.0.1") ? "http" : "https"
        "#{scheme}://#{host}"
      end

      # Resolution order: explicit setup host → general app host → the domain set
      # by the wizard's domain step → a sane local default at first boot.
      def configured_host
        ENV["POWERNODE_SETUP_HOST"].presence ||
          ENV["APP_HOST"].presence ||
          setting_host ||
          "localhost:3000"
      end

      def setting_host
        SiteSetting.get("domain").presence
      rescue StandardError
        nil
      end
    end
  end
end
