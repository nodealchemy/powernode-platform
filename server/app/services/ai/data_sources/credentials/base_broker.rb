# frozen_string_literal: true

module Ai
  module DataSources
    module Credentials
      # Base class + CONTRACT for a dynamic credential broker.
      #
      # WHAT A BROKER DOES: instead of signing with a static stored secret, a broker
      # EXCHANGES the resolved base credential with an external authority (AWS STS,
      # an OAuth2 token endpoint, a Vault dynamic engine, an S3 presigner) for a
      # SHORT-LIVED credential, just before the signed fetch. It slots into
      # QueryService#resolve_credential AFTER the base credential is resolved
      # (static or Vault) and returns something the existing signer layer consumes
      # UNCHANGED.
      #
      # PUBLIC CONTRACT (the registry + QueryService call this):
      #   broker.acquire(data_source:, base_credential:, config:)
      #     -> a credential satisfying the SIGNER CONTRACT
      #        (#decrypted_api_key / #decrypted_api_secret / #[](name)) — either a
      #        BrokeredCredential built from freshly-acquired material, OR the
      #        base_credential unchanged (degrade path / no brokering).
      #
      #   data_source       [Ai::DataSource]
      #   base_credential   [#decrypted_api_key, ...] the resolved STATIC/VAULT cred,
      #                     or nil. Brokers read the BASE secret off this (e.g. OAuth
      #                     client_id/secret, the AWS keys used to call AssumeRole).
      #   config            [Hash] data_source.auth_config["broker"] — broker-specific
      #                     NON-secret knobs (token_url, role_arn, audience, vault_path,
      #                     region, bucket, object_key, skew_seconds, ...). NEVER read
      #                     secrets from here; secrets come from base_credential.
      #
      # SUBCLASS CONTRACT: override the PROTECTED #acquire!(data_source:,
      # base_credential:, config:) to perform the exchange and return a
      # BrokeredCredential (or base_credential to no-op). #acquire! MAY raise; the
      # public #acquire template wraps it in a rescue that degrades to
      # base_credential, so a broker failure NEVER crashes the fetch pipeline.
      #
      # SECURITY (non-negotiable, mirrors QueryService#sign_request! discipline):
      #   - NEVER log/echo/embed a token, secret, session_token, client_secret, or
      #     key material. Rescue blocks log e.class only (or a redacted message).
      #   - Any OUTBOUND HTTP a broker makes (OAuth token_url, OIDC token-exchange,
      #     any config-supplied URL) MUST go through #broker_http_connection, which
      #     returns the SSRF-guarded Faraday connection (validate_url! +
      #     SsrfGuardMiddleware + validate_redirect!). A bare Faraday.new on a
      #     config URL would reintroduce the SSRF/DNS-rebinding hole (e.g. token_url
      #     -> 169.254.169.254). AWS SDK calls hit fixed AWS endpoints and are fine,
      #     but MUST NOT honor a config-supplied endpoint override.
      #   - No long-lived key material is generated or persisted. Acquisition is
      #     audit-logged with a NON-SECRET line (#audit_log).
      class BaseBroker
        # PUBLIC template method. Wraps the subclass #acquire! in a fail-safe rescue:
        # on ANY error, log (redacted) and return base_credential unchanged so the
        # fetch pipeline degrades to the stored credential rather than crashing.
        #
        # @return [#decrypted_api_key, #decrypted_api_secret, #[]] a credential
        #   satisfying the signer contract (BrokeredCredential or base_credential).
        def acquire(data_source:, base_credential:, config:)
          cfg = config.is_a?(Hash) ? config : {}
          acquire!(data_source: data_source, base_credential: base_credential, config: cfg)
        rescue StandardError => e
          # Degrade, never crash. Log class only — an exception message from an HTTP
          # client or the AWS SDK can contain echoed request material.
          audit_log(data_source, "error", error_class: e.class.name)
          base_credential
        end

        protected

        # Subclasses override. Perform the credential exchange and return a
        # BrokeredCredential (or base_credential to no-op). MAY raise — the public
        # #acquire catches and degrades.
        #
        # @return [#decrypted_api_key, ...] the brokered or base credential.
        def acquire!(data_source:, base_credential:, config:)
          raise NotImplementedError, "#{self.class}#acquire! must be implemented"
        end

        # SSRF-guarded Faraday connection for any broker that must call a
        # config-supplied URL (OAuth2 token_url, OIDC token-exchange endpoint).
        #
        # The returned connection carries SsrfGuardMiddleware (re-validates the
        # request URL on the way out) and a redirect callback that re-pins every
        # hop, so a config URL that resolves to a private/loopback/link-local
        # address is REJECTED with HttpConnectionFactory::SsrfError. The caller
        # SHOULD also call HttpConnectionFactory.validate_url!(url) explicitly
        # before dispatch (resolve-and-pin) and then run the request against the
        # ABSOLUTE url so the middleware validates the exact target.
        #
        # NOTE: HttpConnectionFactory.build seeds the connection's base URL from
        # data_source.api_base_url, but a broker dispatches against the absolute
        # token_url (passed to run_request), which the middleware validates per
        # request — the base URL is irrelevant to the guard.
        #
        # @param url [String] the absolute outbound URL (used here only to fail fast
        #   on an obviously bad scheme/host; the connection guards every request).
        # @return [Faraday::Connection] an SSRF-guarded connection.
        def broker_http_connection(url, data_source:, agent: nil, max_redirects: nil)
          # Fail fast (resolve-and-pin) BEFORE building anything so a bad URL raises
          # the same SsrfError the middleware would, with no socket opened.
          Ai::DataSources::HttpConnectionFactory.validate_url!(url) if url.present?
          # max_redirects: 0 lets a token-exchange broker forbid redirect-following —
          # a token endpoint should never 3xx, and following a 307/308 cross-host
          # could replay a body-mode client_secret to the redirect target.
          Ai::DataSources::HttpConnectionFactory.build(
            data_source: data_source, agent: agent, max_redirects: max_redirects
          )
        end

        # Tolerant jsonb read: returns the first present value among +keys+, checking
        # both String and Symbol spellings (auth_config round-trips as string keys
        # from the DB but may be symbol-keyed in tests). Blank-but-present values are
        # skipped so a later fallback key can win.
        #
        # @example
        #   cfg(config, :token_url)            # => "https://idp/token"
        #   cfg(config, :skew_seconds) || 30   # tolerant default
        def cfg(config, *keys)
          return nil unless config.is_a?(Hash)

          keys.each do |key|
            [key.to_s, key.to_sym].each do |variant|
              value = config[variant]
              return value if value.respond_to?(:empty?) ? !value.empty? : !value.nil?
            end
          end
          nil
        end

        # Emit a single NON-SECRET audit line for a key operation. Records the
        # broker type, source slug, outcome, and (optionally) the lease expiry —
        # never any token/secret/material. Mirrors the "log e.class only" discipline
        # used throughout the data-source pipeline.
        #
        # @param data_source [Ai::DataSource, nil]
        # @param outcome [String] e.g. "acquired", "cached", "skipped", "error".
        # @param meta [Hash] additional NON-SECRET key/values (expires_at:, reason:,
        #   error_class:, ...). Values are interpolated verbatim, so callers MUST
        #   pass only non-secret data.
        def audit_log(data_source, outcome, **meta)
          slug = safe_slug(data_source)
          parts = ["broker=#{broker_type}", "source=#{slug}", "outcome=#{outcome}"]
          meta.each { |k, v| parts << "#{k}=#{v}" }
          Rails.logger.info("[Credentials::#{self.class.name.demodulize}] #{parts.join(' ')}")
        rescue StandardError
          nil
        end

        # The broker's registry type token, derived from the class name
        # (Oauth2ClientCredentialsBroker => "oauth2_client_credentials"). Used only
        # in audit lines; subclasses MAY override for a canonical token.
        def broker_type
          self.class.name.demodulize.sub(/Broker\z/, "").underscore
        rescue StandardError
          "unknown"
        end

        # Compute the cached lease seconds from an absolute expiry (delegates to
        # BrokerCache.ttl_with_skew). Convenience for subclasses building the
        # { material:, ttl_seconds: } block result.
        def lease_seconds(expires_at:, skew_seconds: 0)
          Ai::DataSources::Credentials::BrokerCache.ttl_with_skew(
            expires_at: expires_at, skew_seconds: skew_seconds.to_i
          )
        end

        private

        def safe_slug(data_source)
          data_source.respond_to?(:slug) ? data_source.slug : "unknown"
        rescue StandardError
          "unknown"
        end
      end
    end
  end
end
