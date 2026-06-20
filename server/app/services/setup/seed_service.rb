# frozen_string_literal: true

module Setup
  # Web-safe, programmatic seed entry for the wizard's final (optional) step.
  #
  # Core-pure: routes through a generic extension seam (the :account_seeder
  # provider) so core names no extension. In core mode — or any build where no
  # extension registers a seeder — it is a safe no-op. When a seeder is present it
  # is called with the collected domain so seed data is domain-parameterized
  # (SiteSetting "domain", default "powernode.internal" when unset — closes the
  # no-hardcoded-hostnames thread by construction).
  #
  # The seeder contract: `call(account:, domain:, only_if_empty:)`, idempotent.
  class SeedService
    DEFAULT_DOMAIN = "powernode.internal"

    # @return [Hash] { seeded: Boolean, reason: String (when not seeded) }
    def self.run!(account, only_if_empty: true)
      seeder = Powernode::ExtensionRegistry.provider(:account_seeder)
      return { seeded: false, reason: "no_seeder" } if seeder.nil?

      seeder.call(account: account, domain: domain_for, only_if_empty: only_if_empty)
      { seeded: true }
    rescue StandardError => e
      Rails.logger.error("[Setup::SeedService] seed failed: #{e.class}: #{e.message}")
      { seeded: false, reason: "error" }
    end

    def self.domain_for
      SiteSetting.get("domain").presence || DEFAULT_DOMAIN
    end
  end
end
