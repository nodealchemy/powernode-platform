# frozen_string_literal: true

module Ai
  module DataSources
    module Credentials
      # The no-op / generic-fallback broker: returns the resolved base credential
      # UNCHANGED (static stored secret or the Vault view). This is what the
      # Registry resolves for an unknown, blank, or "static" broker type, mirroring
      # the way SignerRegistry falls back to NoneSigner — adding a source with an
      # unrecognized broker type degrades safely to "no brokering" instead of
      # raising.
      #
      # There is nothing to exchange and no outbound call, so #acquire! cannot fail;
      # the BaseBroker rescue is moot here but the contract is identical.
      class StaticBroker < BaseBroker
        protected

        def acquire!(data_source:, base_credential:, config:)
          base_credential
        end

        # Canonical registry token (BaseBroker#broker_type would yield "static"
        # from the class name, but pin it explicitly for clarity in audit lines).
        def broker_type
          "static"
        end
      end
    end
  end
end
