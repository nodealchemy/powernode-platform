# frozen_string_literal: true

require "securerandom"
require "digest"
require "base64"
require "uri"
require "json"

module Ai
  module DataSources
    # x-com-provider campaign (I1) — provider-agnostic OAuth 2.0 Authorization
    # Code + PKCE (RFC 7636) connect flow for a data source's stored credential
    # (Ai::DataSourceCredential#client_id/#client_secret, added in I2).
    #
    # TWO ENTRY POINTS, matching Api::V1::Ai::DataSourceOauthController's actions:
    #
    #   #build_authorize_request — called from the JWT-authenticated :authorize
    #     action. Mints a random `state` + PKCE `code_verifier`/`code_challenge`,
    #     stashes { code_verifier, account_id, user_id, data_source_id,
    #     credential_id, redirect_uri, scopes } server-side keyed by `state`
    #     (Rails.cache, namespaced, ~10 min TTL, single-use), and returns the
    #     provider's authorization URL. NEVER returns the code_verifier.
    #
    #   #handle_callback — called from the UNAUTHENTICATED :callback action (a
    #     top-level browser redirect from the provider carries no JWT). The
    #     ENTIRE authorization/CSRF defense is the `state` value: it is looked
    #     up, consumed (single-use — deleted whether it resolves or not), and
    #     its own data_source_id is cross-checked against the path's — the path
    #     is NEVER trusted over the state. On success, exchanges the code (+
    #     code_verifier) at auth_config["token_url"] and persists the tokens
    #     onto the SAME credential the state was minted for.
    #
    # STATE STORAGE CHOICE: Rails.cache over a new AR model/migration. The
    # pending record is small, short-lived (~10 min), single-use, and never
    # queried by anything but its own state key — an AR table would need a
    # migration, an index, and a sweep job for exactly the lifecycle Rails.cache
    # already gives for free (TTL expiry). Rails.cache read-then-delete is NOT
    # perfectly atomic (a concurrent replay within that window could observe the
    # value twice) — acceptable here because it only tightens an already-narrow,
    # one-shot CSRF-token window; a real atomic guarantee would need a
    # distributed lock for a benefit this endpoint's threat model doesn't need.
    class OauthAuthorizationCodeService
      class ConfigError < StandardError; end

      CACHE_KEY_PREFIX = "ai:data_source_oauth:pending"
      PENDING_TTL = 10.minutes

      # RFC 7636 code_verifier must be 43-128 chars of [A-Za-z0-9-._~]; 64 raw
      # bytes of urlsafe_base64 lands at ~86 chars, comfortably inside the range.
      CODE_VERIFIER_BYTES = 64
      # >=32 bytes of entropy for the CSRF state token, per the campaign brief.
      STATE_BYTES = 32

      FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"

      # Mirrors Oauth2ClientCredentialsBroker::MAX_TOKEN_TTL_SECONDS — a token
      # endpoint returning an absurd expires_in must not pin a stale bearer for
      # years. Kept as its own constant (this service isn't a BaseBroker
      # subclass) — keep the two in sync if either changes.
      MAX_TOKEN_TTL_SECONDS = 86_400

      # ------------------------------------------------------------------
      # Endpoint A — POST .../oauth/authorize
      # ------------------------------------------------------------------

      # @param data_source [Ai::DataSource] already account-scoped by the caller.
      # @param user [User] the initiating user (JWT-authenticated).
      # @param account [Account] the initiating account.
      # @param credential_id [String, nil] optional — defaults to the source's
      #   #active_credential (the one holding the OAuth app's client_id/secret).
      # @return [Hash] { authorization_url:, redirect_uri:, state: }
      # @raise [ConfigError] when the credential or auth_config is incomplete.
      def build_authorize_request(data_source:, user:, account:, credential_id: nil)
        credential = resolve_credential(data_source, credential_id)
        if credential&.client_id.blank?
          raise ConfigError, "No credential with a client_id is configured for this data source"
        end

        authorize_url = auth_cfg(data_source, :authorize_url)
        raise ConfigError, "Data source auth_config is missing authorize_url" if authorize_url.blank?
        raise ConfigError, "Data source auth_config is missing token_url" if auth_cfg(data_source, :token_url).blank?

        state = SecureRandom.urlsafe_base64(STATE_BYTES)
        code_verifier = SecureRandom.urlsafe_base64(CODE_VERIFIER_BYTES)
        code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
        scopes = requested_scopes(data_source)
        redirect_uri = build_redirect_uri(data_source: data_source, account: account)

        store_pending_state!(
          state: state,
          account_id: account.id,
          user_id: user.id,
          data_source_id: data_source.id,
          credential_id: credential.id,
          code_verifier: code_verifier,
          redirect_uri: redirect_uri,
          scopes: scopes
        )

        query = {
          client_id: credential.client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: scopes.join(" "),
          state: state,
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        }.compact

        {
          authorization_url: "#{authorize_url}?#{query.to_query}",
          redirect_uri: redirect_uri,
          state: state
        }
      end

      # ------------------------------------------------------------------
      # Endpoint B — GET|POST .../oauth/callback (UNAUTHENTICATED)
      # ------------------------------------------------------------------

      # @param path_data_source_id [String] the :data_source_id route param —
      #   used ONLY to cross-check against the state's own data_source_id;
      #   never trusted to look anything up on its own.
      # @param state [String, nil]
      # @param code [String, nil]
      # @param error [String, nil] set by the provider when the user denied consent.
      # @return [Hash] { success:, error:, scopes:, account_id:, user_id:,
      #   data_source_id: } — the id fields are populated whenever a pending
      #   state was found (success or not) so the controller can attribute an
      #   audit log entry; they are nil when the state itself couldn't be resolved.
      def handle_callback(path_data_source_id:, state:, code:, error: nil)
        ids = {}

        return failure("The OAuth provider reported an error: #{error}") if error.present?
        return failure("Missing state") if state.blank?
        return failure("Missing authorization code") if code.blank?

        pending = consume_pending_state(state)
        return failure("OAuth state is missing, unknown, or expired") if pending.nil?

        ids = pending.slice(:account_id, :user_id, :data_source_id)

        # Defense in depth: the path is NEVER trusted over the state — a caller
        # hitting /data_sources/OTHER_ID/oauth/callback with a state minted for
        # a different source is rejected even though the state itself is valid.
        if path_data_source_id.present? && path_data_source_id.to_s != pending[:data_source_id].to_s
          return failure("OAuth state does not match the requested data source", **ids)
        end

        data_source = ::Ai::DataSource.find_by(id: pending[:data_source_id])
        credential = data_source&.credentials&.find_by(id: pending[:credential_id])
        if credential.nil? || credential.account_id.to_s != pending[:account_id].to_s
          return failure("The data source or credential no longer exists", **ids)
        end

        token_url = auth_cfg(data_source, :token_url)
        return failure("Data source auth_config is missing token_url", **ids) if token_url.blank?

        begin
          ::Ai::DataSources::HttpConnectionFactory.validate_url!(token_url)
        rescue ::Ai::DataSources::HttpConnectionFactory::SsrfError => e
          Rails.logger.warn("[OauthAuthorizationCodeService] token_url rejected: #{e.class}")
          return failure("The token endpoint URL is not allowed", **ids)
        end

        access_token, refresh_token, expires_in, scope = exchange_code_for_token(
          data_source: data_source,
          credential: credential,
          token_url: token_url,
          code: code,
          code_verifier: pending[:code_verifier],
          redirect_uri: pending[:redirect_uri]
        )

        if access_token.blank?
          credential.record_failure!("OAuth authorization-code token exchange failed")
          return failure("Failed to exchange the authorization code for a token", **ids)
        end

        scopes = normalize_scopes(scope).presence || pending[:scopes] || []
        persist_tokens!(credential, access_token: access_token, refresh_token: refresh_token,
                        expires_in: expires_in, scopes: scopes)
        credential.record_success!

        { success: true, error: nil, scopes: scopes, **ids }
      rescue StandardError => e
        Rails.logger.error("[OauthAuthorizationCodeService] callback failed: #{e.class}")
        failure("The OAuth callback could not be processed", **ids)
      end

      private

      def failure(message, account_id: nil, user_id: nil, data_source_id: nil)
        {
          success: false, error: message, scopes: nil,
          account_id: account_id, user_id: user_id, data_source_id: data_source_id
        }
      end

      def resolve_credential(data_source, credential_id)
        return data_source.credentials.find_by(id: credential_id) if credential_id.present?

        data_source.active_credential
      end

      # Absolute callback URL, computed (never stored) from the platform's
      # configured public base URL (PublicUrlResolver) + the named route. This
      # is what resolves I2's parked redirect_uri question, and what the UI
      # shows the operator to register on the provider's app-config page.
      def build_redirect_uri(data_source:, account:)
        path = Rails.application.routes.url_helpers.api_v1_ai_data_source_oauth_callback_path(
          data_source_id: data_source.id
        )
        ::PublicUrlResolver.url_for(path, account: account)
      end

      def store_pending_state!(state:, **payload)
        Rails.cache.write(cache_key(state), payload, expires_in: PENDING_TTL)
      end

      # Single-use: delete on read regardless of whether the key resolved, so a
      # replayed callback (same state twice) always sees a miss the second time.
      def consume_pending_state(state)
        key = cache_key(state)
        payload = Rails.cache.read(key)
        Rails.cache.delete(key)
        payload
      end

      def cache_key(state)
        "#{CACHE_KEY_PREFIX}:#{state}"
      end

      # POST the token endpoint through the SSRF-guarded connection. Returns
      # [access_token, refresh_token, expires_in_seconds_or_nil, scope]. NEVER
      # logs the code, verifier, tokens, or client_secret.
      #
      # Response parsing + the Basic client-auth header are shared with
      # Oauth2AuthorizationCodeBroker's refresh call via OauthTokenEndpoint — this
      # method keeps its own transport-error rescue (returns the nil-tuple
      # sentinel) rather than raising, which is THIS service's convention (the
      # broker instead lets transport errors propagate to BaseBroker#acquire).
      def exchange_code_for_token(data_source:, credential:, token_url:, code:, code_verifier:, redirect_uri:)
        form = {
          "grant_type" => "authorization_code",
          "code" => code,
          "redirect_uri" => redirect_uri,
          "code_verifier" => code_verifier,
          "client_id" => credential.client_id
        }

        headers = { "Content-Type" => FORM_CONTENT_TYPE, "Accept" => "application/json" }
        # X (and most providers) expect HTTP Basic client auth for a confidential
        # client; a public client (no client_secret configured) omits it and
        # relies on PKCE + the client_id already present in the form body.
        if credential.client_secret.present?
          headers["Authorization"] = ::Ai::DataSources::OauthTokenEndpoint.basic_auth_header(
            credential.client_id, credential.client_secret
          )
        end

        # max_redirects: 0 — a token endpoint must never redirect (mirrors
        # Oauth2ClientCredentialsBroker: following a 3xx could replay the code,
        # verifier, or client_secret to an unintended host).
        conn = ::Ai::DataSources::HttpConnectionFactory.build(data_source: data_source, max_redirects: 0)
        response = conn.run_request(:post, token_url, URI.encode_www_form(form), headers)
        result = ::Ai::DataSources::OauthTokenEndpoint.parse_response(response, max_ttl_seconds: MAX_TOKEN_TTL_SECONDS)
        [result["access_token"], result["refresh_token"], result["expires_in"], result["scope"]]
      rescue StandardError => e
        Rails.logger.error("[OauthAuthorizationCodeService] token exchange transport error: #{e.class}")
        [nil, nil, nil, nil]
      end

      # Persists the exchanged tokens onto the credential using the raw
      # encrypted_* column names (there is no alias_attribute for access_token/
      # refresh_token — only client_id/client_secret have one), mirroring how
      # DataSourceCredentialsController#credential_params already writes
      # encrypted_api_key/encrypted_api_secret directly.
      def persist_tokens!(credential, access_token:, refresh_token:, expires_in:, scopes:)
        credential.update!(
          encrypted_access_token: access_token,
          # X's authorization_code grant always issues a refresh_token on the
          # FIRST exchange; a later refresh (I3) may omit it, meaning "keep
          # rotating the existing one" per RFC 6749 sec. 6.
          encrypted_refresh_token: refresh_token.presence || credential.encrypted_refresh_token,
          access_token_expires_at: expires_in ? Time.current + expires_in : nil,
          oauth_scopes: scopes
        )
      end

      def normalize_scopes(scope)
        ::Ai::DataSources::OauthTokenEndpoint.normalize_scopes(scope)
      end

      def requested_scopes(data_source)
        raw = auth_cfg(data_source, :scopes) || auth_cfg(data_source, :scope)
        case raw
        when Array then raw.map(&:to_s)
        when String then raw.split(/[\s,]+/).reject(&:blank?)
        else []
        end
      end

      # Tolerant jsonb read: returns the first present value among +keys+,
      # checking both String and Symbol spellings (auth_config round-trips as
      # string keys from the DB but may be symbol-keyed in tests/specs).
      # Mirrors BaseBroker#cfg.
      def auth_cfg(data_source, *keys)
        config = data_source.respond_to?(:auth_config) ? (data_source.auth_config || {}) : {}
        return nil unless config.is_a?(Hash)

        keys.each do |key|
          [key.to_s, key.to_sym].each do |variant|
            value = config[variant]
            return value if value.respond_to?(:empty?) ? !value.empty? : !value.nil?
          end
        end
        nil
      end
    end
  end
end
