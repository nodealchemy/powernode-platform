# frozen_string_literal: true

require "digest"
require "json"

module Ai
  module DataSources
    module Credentials
      # Exchanges a stored AT Protocol (Bluesky) APP PASSWORD for a SHORT-LIVED
      # session accessJwt via com.atproto.server.createSession, just before the
      # signed fetch — the app-password counterpart to
      # Oauth2ClientCredentialsBroker's client_credentials exchange. AT Protocol
      # has no OAuth2 authorization-code/redirect dance to attach to a stored
      # credential up front (unlike x-com/linkedin/reddit/youtube) — createSession
      # IS the login, taking the account handle + a scoped, revocable app
      # password (never the main account password) directly.
      #
      # SECRETS (off the BASE credential, never config — mirrors
      # Oauth2ClientCredentialsBroker's reuse of the generic api_key/api_secret
      # pair for a non-"api key" secret shape):
      #   base_credential.decrypted_api_key    -> identifier (handle, e.g.
      #                                            "alice.bsky.social", or a DID)
      #   base_credential.decrypted_api_secret -> app password (minted at
      #                                            https://bsky.app/settings/app-passwords)
      #
      # HOST: the session is created against data_source.api_base_url — the SAME
      # host the signed read/write calls target (mirrors the Mastodon template's
      # per-instance api_base_url; the operator points both at their PDS, e.g.
      # https://bsky.social for a hosted account, or their self-hosted PDS's URL).
      #
      # RETURN: a BrokeredCredential whose #decrypted_api_key is the accessJwt, so
      # the existing BearerSigner sends "Authorization: Bearer <accessJwt>"
      # UNCHANGED — same return shape as every other bearer-yielding broker.
      #
      # CACHING (BrokerCache, mirrors Oauth2ClientCredentialsBroker exactly): the
      # accessJwt is cached for (lease - skew) seconds so a burst of signed
      # requests does not call createSession (re-sending the app password) on
      # every fetch. The lease is read from the accessJwt's own "exp" claim
      # (decoded WITHOUT signature verification — we already trust the HTTPS
      # response that just handed it to us; we only want the expiry hint, never
      # to authorize anything on the claim). A token whose exp can't be decoded
      # falls back to DEFAULT_SESSION_TTL_SECONDS so the broker still degrades to
      # a conservative, bounded lease rather than caching forever.
      #
      # NOT IMPLEMENTED (parked — provider-wave-2 W2): refreshing an existing
      # session via com.atproto.server.refreshSession using the accompanying
      # refreshJwt. That would need either a persisted-credential design (a
      # one-time "connect" step storing the initial session tokens, mirroring
      # OauthAuthorizationCodeService) or a two-tier cache tracking a separately-
      # expiring refreshJwt — materially more than this broker. Instead, every
      # cache-expiry simply re-authenticates via createSession, which is safe
      # (app passwords are scoped/revocable secrets meant for exactly this
      # programmatic use) at the cost of one extra call per lease cycle versus a
      # refresh-token grant.
      #
      # SECURITY: the createSession POST goes through #broker_http_connection
      # (SSRF-guarded, max_redirects: 0 — a login endpoint must never redirect).
      # The app password, accessJwt, and refreshJwt are NEVER logged, echoed, or
      # placed in an exception message.
      class AtprotoAppPasswordBroker < BaseBroker
        SESSION_PATH = "/xrpc/com.atproto.server.createSession"
        DEFAULT_SKEW_SECONDS = 60
        # Conservative fallback lease when the accessJwt's "exp" claim can't be
        # decoded — short enough that a broker relying on this path re-acquires
        # often rather than caching a token whose real lifetime is unknown.
        DEFAULT_SESSION_TTL_SECONDS = 300
        # Mirrors the sibling brokers' daily ceiling — an implausible "exp" must
        # not pin a cached session for years.
        MAX_SESSION_TTL_SECONDS = 86_400

        protected

        def acquire!(data_source:, base_credential:, config:)
          identifier = base_credential&.decrypted_api_key
          app_password = base_credential&.decrypted_api_secret
          return base_credential if identifier.blank? || app_password.blank?

          base_url = data_source.respond_to?(:api_base_url) ? data_source.api_base_url.to_s : ""
          return base_credential if base_url.blank?

          skew = (cfg(config, :skew_seconds) || DEFAULT_SKEW_SECONDS).to_i
          key = cache_key(data_source: data_source, identifier: identifier, app_password: app_password)

          material = BrokerCache.fetch(key) do
            access_jwt = create_session(
              data_source: data_source, base_url: base_url,
              identifier: identifier, app_password: app_password
            )
            next { material: nil, ttl_seconds: 0 } if access_jwt.blank?

            expires_at = jwt_expiry(access_jwt) || (Time.current + DEFAULT_SESSION_TTL_SECONDS)
            audit_log(data_source, "acquired", expires_at: iso(expires_at))
            {
              material: { "token" => access_jwt, "expires_at" => iso(expires_at) }.compact,
              ttl_seconds: lease_seconds(expires_at: expires_at, skew_seconds: skew)
            }
          end

          return base_credential if material.nil? || material["token"].blank?

          BrokeredCredential.new(material, expires_at: material["expires_at"])
        end

        # Canonical registry token (matches Registry::BROKERS key).
        def broker_type
          "atproto_app_password"
        end

        private

        # POST com.atproto.server.createSession through the SSRF-guarded
        # connection. Returns the accessJwt String, or nil on any non-2xx/
        # JSON-less/token-less response. NEVER logs the app_password, accessJwt,
        # or refreshJwt.
        def create_session(data_source:, base_url:, identifier:, app_password:)
          url = "#{base_url.chomp('/')}#{SESSION_PATH}"
          headers = { "Content-Type" => "application/json", "Accept" => "application/json" }
          body = { "identifier" => identifier, "password" => app_password }.to_json

          # max_redirects: 0 — a login endpoint must never redirect; following a
          # 3xx could replay the app password to an unintended host.
          conn = broker_http_connection(url, data_source: data_source, max_redirects: 0)
          response = conn.run_request(:post, url, body, headers)
          parse_session_response(response)
        end

        # Parses createSession's JSON body. Returns the accessJwt, or nil on a
        # non-2xx status, non-JSON body, or a body missing accessJwt — WITHOUT
        # surfacing any response content (which could echo an error detail).
        def parse_session_response(response)
          return nil unless response&.respond_to?(:status)
          return nil unless (200..299).cover?(response.status)

          body = response.body
          parsed = body.is_a?(Hash) ? body : safe_parse_json(body)
          return nil unless parsed.is_a?(Hash)

          (parsed["accessJwt"] || parsed[:accessJwt]).presence
        end

        def safe_parse_json(body)
          str = body.to_s
          return nil if str.empty?

          JSON.parse(str)
        rescue JSON::ParserError
          nil
        end

        # Peek at the accessJwt's "exp" claim WITHOUT verifying its signature —
        # we already trust the HTTPS response that just handed us the token; this
        # is only a lease-length hint for BrokerCache, never an authorization
        # decision. Any decode failure (malformed token, missing claim) yields
        # nil so the caller falls back to DEFAULT_SESSION_TTL_SECONDS.
        def jwt_expiry(access_jwt)
          payload = JWT.decode(access_jwt, nil, false)[0]
          exp = payload["exp"]
          return nil unless exp

          expires_at = Time.zone ? Time.zone.at(exp.to_i) : Time.at(exp.to_i)
          # Clamp an implausible exp the same way the sibling brokers clamp an
          # absurd expires_in.
          ceiling = Time.current + MAX_SESSION_TTL_SECONDS
          expires_at > ceiling ? ceiling : expires_at
        rescue StandardError
          nil
        end

        # Stable, NON-secret cache key. Mixes a SHA256 fingerprint of the app
        # password (so rotating it naturally invalidates the cache) without
        # storing/logging the password itself.
        def cache_key(data_source:, identifier:, app_password:)
          source_id = data_source.respond_to?(:id) ? data_source.id : "unknown"
          fingerprint = Digest::SHA256.hexdigest("#{identifier}:#{app_password}")
          "atproto:#{source_id}:#{fingerprint}"
        end

        def iso(time)
          time&.utc&.iso8601
        end
      end
    end
  end
end
