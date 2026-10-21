# frozen_string_literal: true

module Setup
  # Re-renders the Traefik dynamic config after the wizard changed trusted hosts,
  # so new domains take effect in production without waiting for the next write.
  # Never raises: returns a warning string on failure (nil on success or no-op).
  # No-op in development, where there is no Traefik.
  class IngressRefresher
    def self.call(account:)
      return nil if Rails.env.development?

      Core::IngressConfigWriter.write!(account: account)
      nil
    rescue StandardError => e
      # Class name only: messages from the writer can embed file paths or key state.
      Rails.logger.error("[Setup::IngressRefresher] ingress write failed: #{e.class}")
      "Domains were saved, but the reverse-proxy config could not be rewritten (#{e.class}). " \
        "It will be picked up on the next ingress write."
    end
  end
end
