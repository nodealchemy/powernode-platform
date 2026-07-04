# frozen_string_literal: true

require "uri"

module Ai
  module DataSources
    module Credentials
      # Silently keeps an OAuth2 Authorization-Code credential's (I1 + I2)
      # access_token FRESH just before a signed fetch — the user-context
      # counterpart to Oauth2ClientCredentialsBroker's app-only client_credentials
      # exchange. Unlike that broker, the BASE credential here already carries a
      # real access_token + refresh_token (persisted by
      # OauthAuthorizationCodeService#handle_callback); this broker's job is to
      # decide whether the stored token is still good and, if not, refresh it via
      # the RFC 6749 sec. 6 `refresh_token` grant.
      #
      # BASE CREDENTIAL (an Ai::DataSourceCredential — NOT a lightweight
      # key/secret pair like the other brokers read):
      #   base_credential.decrypted_access_token   -> the currently-stored bearer
      #   base_credential.decrypted_refresh_token   -> used to mint a new one
      #   base_credential.client_id / #client_secret -> the app's OAuth2 client
      #   base_credential.needs_refresh?(buffer:)    -> I2's near-expiry check
      #
      # CONFIG (data_source.auth_config["broker"], NON-secret):
      #   "token_url"              [String]  REQUIRED — the OAuth2 token endpoint.
      #   "refresh_buffer_seconds" [Integer] optional — passed to #needs_refresh?
      #                                      as `buffer:` (default 60, mirrors the
      #                                      model's own default).
      #
      # RETURN: a BrokeredCredential whose #decrypted_api_key is the (possibly
      # just-refreshed) access_token, so the existing BearerSigner sends
      # "Authorization: Bearer <access_token>" UNCHANGED — mirrors
      # Oauth2ClientCredentialsBroker's return shape exactly.
      #
      # NO CACHING: unlike the other brokers, the "cache" IS the credential row
      # itself (access_token_expires_at already tells us freshness) — there is no
      # separate BrokerCache lease to manage.
      #
      # FAILURE HANDLING (deliberately NOT the generic silent BaseBroker degrade):
      # a failed refresh calls #record_failure! on the credential (a persisted,
      # operator-visible signal — last_error / consecutive_failures) and RAISES a
      # scoped RefreshError with a secret-free message, rather than quietly
      # returning [nil, nil, nil] from a private helper. BaseBroker#acquire still
      # catches the raise and degrades to base_credential (a broker fault must
      # never crash the fetch pipeline), but the failure is never swallowed
      # without a trace the way a bare `return base_credential` would be.
      #
      # SECURITY: the refresh POST goes through #broker_http_connection (SSRF-
      # guarded, max_redirects: 0 — a token endpoint must never redirect). The
      # access_token, refresh_token, and client_secret are NEVER logged, echoed,
      # or placed in an exception message.
      class Oauth2AuthorizationCodeBroker < BaseBroker
        # Raised (and caught by BaseBroker#acquire's degrade-and-log rescue) when
        # the refresh_token grant fails to yield a usable access_token. Kept as a
        # distinct class so the audit line's error_class names this failure
        # specifically rather than a generic StandardError.
        class RefreshError < StandardError; end

        GRANT_TYPE = "refresh_token"
        DEFAULT_REFRESH_BUFFER_SECONDS = 60
        FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"
        # Mirrors Oauth2ClientCredentialsBroker::MAX_TOKEN_TTL_SECONDS — a refresh
        # response returning an absurd expires_in must not pin a stale bearer for
        # years.
        MAX_TOKEN_TTL_SECONDS = 86_400

        protected

        def acquire!(data_source:, base_credential:, config:)
          return base_credential unless base_credential.respond_to?(:decrypted_refresh_token)

          access_token = base_credential.decrypted_access_token
          buffer = (cfg(config, :refresh_buffer_seconds) || DEFAULT_REFRESH_BUFFER_SECONDS).to_i

          if access_token.present? && !base_credential.needs_refresh?(buffer: buffer)
            return bearer_credential(access_token, base_credential.access_token_expires_at)
          end

          refresh_token = base_credential.decrypted_refresh_token
          return base_credential if refresh_token.blank?

          token_url = cfg(config, :token_url).to_s
          return base_credential if token_url.blank?

          result = refresh_access_token(
            data_source: data_source, base_credential: base_credential,
            token_url: token_url, refresh_token: refresh_token
          )

          if result["access_token"].blank?
            base_credential.record_failure!("OAuth2 token refresh failed") if base_credential.respond_to?(:record_failure!)
            raise RefreshError, "token endpoint returned no access_token on refresh"
          end

          persist_refreshed_tokens!(base_credential, result)
          base_credential.record_success! if base_credential.respond_to?(:record_success!)
          audit_log(data_source, "refreshed", expires_at: iso(base_credential.access_token_expires_at))

          bearer_credential(result["access_token"], base_credential.access_token_expires_at)
        end

        # Canonical registry token (matches Registry::BROKERS key).
        def broker_type
          "oauth2_authorization_code"
        end

        private

        # Wrap an access_token (fresh-from-storage or just-refreshed) in the
        # standard bearer material shape — same "token" key
        # Oauth2ClientCredentialsBroker uses, so BearerSigner reads it identically.
        def bearer_credential(access_token, expires_at)
          BrokeredCredential.new({ "token" => access_token }, expires_at: expires_at)
        end

        # POST the token endpoint's refresh_token grant through the SSRF-guarded
        # connection. Returns the OauthTokenEndpoint result Hash (possibly empty
        # on a non-2xx/token-less response — the caller decides that's a failure).
        # Deliberately does NOT rescue: an SSRF rejection or transport error
        # propagates to BaseBroker#acquire's degrade-and-log rescue, mirroring
        # Oauth2ClientCredentialsBroker#request_token's convention exactly. NEVER
        # logs the refresh_token, access_token, or client_secret.
        def refresh_access_token(data_source:, base_credential:, token_url:, refresh_token:)
          form = { "grant_type" => GRANT_TYPE, "refresh_token" => refresh_token }

          headers = { "Content-Type" => FORM_CONTENT_TYPE, "Accept" => "application/json" }
          client_id = base_credential.client_id
          client_secret = base_credential.client_secret
          if client_secret.present?
            headers["Authorization"] = ::Ai::DataSources::OauthTokenEndpoint.basic_auth_header(client_id, client_secret)
          elsif client_id.present?
            # Public client: no secret to authenticate with — identify via the
            # form body instead (mirrors OauthAuthorizationCodeService's exchange).
            form["client_id"] = client_id
          end

          conn = broker_http_connection(token_url, data_source: data_source, max_redirects: 0)
          response = conn.run_request(:post, token_url, URI.encode_www_form(form), headers)
          ::Ai::DataSources::OauthTokenEndpoint.parse_response(response, max_ttl_seconds: MAX_TOKEN_TTL_SECONDS)
        end

        # Persist the refreshed tokens onto the credential's raw encrypted_*
        # columns (mirrors OauthAuthorizationCodeService#persist_tokens!). A
        # provider that omits refresh_token on this response keeps rotating the
        # EXISTING one per RFC 6749 sec. 6 — never blanked out.
        def persist_refreshed_tokens!(credential, result)
          attrs = {
            encrypted_access_token: result["access_token"],
            encrypted_refresh_token: result["refresh_token"].presence || credential.encrypted_refresh_token,
            access_token_expires_at: result["expires_in"] ? Time.current + result["expires_in"] : nil
          }
          scopes = ::Ai::DataSources::OauthTokenEndpoint.normalize_scopes(result["scope"])
          attrs[:oauth_scopes] = scopes if scopes.present?
          credential.update!(attrs)
        end

        def iso(time)
          time&.utc&.iso8601
        end
      end
    end
  end
end
