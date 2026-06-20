# frozen_string_literal: true

module Setup
  # One-time bootstrap token gating the unauthenticated first-admin endpoint.
  #
  # The token runs *before any user exists*, so it cannot use JWT. Only the
  # SHA256 digest is persisted (in AdminSetting, so it is shared across all puma
  # workers and survives a restart); the raw token exists only in memory and in
  # the URL printed to the service console at boot (see Setup::BootstrapService).
  # It is single-use: cleared the moment the first admin is created, after which
  # the entire unauthenticated path is dead (the endpoint also 409s on User.exists?).
  #
  # NB: this is a setup *nonce*, not key material — printing it to the operator's
  # console is the intended delivery channel, not a crypto-safety violation.
  class BootstrapToken
    SETTING_KEY = "setup.bootstrap_token_digest"

    class << self
      # Generate a fresh token, persist its digest, and return the RAW token.
      # Regenerating overwrites any prior digest, invalidating earlier URLs.
      # @return [String] the raw token (caller must not persist it)
      def generate!
        raw = SecureRandom.urlsafe_base64(32)
        AdminSetting.set(SETTING_KEY, digest(raw))
        raw
      end

      # @return [Boolean] whether a bootstrap digest is currently stored
      def present?
        stored_digest.present?
      end

      # Constant-time verification of a presented raw token against the stored
      # digest. Returns false for blank tokens or when no digest is stored.
      # @param token [String, nil]
      # @return [Boolean]
      def verify(token)
        return false if token.blank?

        stored = stored_digest
        candidate = digest(token)
        # secure_compare requires equal-length strings; guard the (astronomically
        # unlikely) case where the stored value did not round-trip as a 64-char hex.
        return false unless stored.is_a?(String) && stored.bytesize == candidate.bytesize

        ActiveSupport::SecurityUtils.secure_compare(candidate, stored)
      end

      # Invalidate the token (called once the first admin is created).
      def clear!
        AdminSetting.where(key: SETTING_KEY).delete_all
      end

      private

      def stored_digest
        AdminSetting.get(SETTING_KEY).to_s.presence
      end

      def digest(token)
        Digest::SHA256.hexdigest(token.to_s)
      end
    end
  end
end
