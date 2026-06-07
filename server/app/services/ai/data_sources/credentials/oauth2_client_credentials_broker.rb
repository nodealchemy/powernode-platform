# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "uri"

module Ai
  module DataSources
    module Credentials
      # Exchanges a stored OAuth2 CLIENT (client_id + client_secret) for a
      # SHORT-LIVED bearer access_token via the RFC 6749 `client_credentials`
      # grant, just before the signed fetch. The returned BrokeredCredential's
      # #decrypted_api_key is the access_token, so the existing BearerSigner sends
      # "Authorization: Bearer <access_token>" UNCHANGED.
      #
      # SECRETS (off the BASE credential, never config):
      #   base_credential.decrypted_api_key    -> client_id
      #   base_credential.decrypted_api_secret -> client_secret
      #
      # CONFIG (data_source.auth_config["broker"], NON-secret knobs):
      #   "token_url"     [String]  REQUIRED — the OAuth2 token endpoint.
      #   "scope"         [String]  optional — space-delimited scopes.
      #   "audience"      [String]  optional — audience/resource (Auth0 etc.).
      #   "client_auth"   [String]  "basic" (default) sends HTTP Basic
      #                             Authorization; "body" puts client_id +
      #                             client_secret in the form body instead.
      #   "skew_seconds"  [Integer] safety margin trimmed off the lease before
      #                             caching (default 60).
      #
      # SECURITY:
      #   - token_url is OPERATOR config, so the POST goes through the SSRF-guarded
      #     #broker_http_connection (validate_url! + SsrfGuardMiddleware +
      #     validate_redirect!) dispatched against the ABSOLUTE token_url — NEVER a
      #     bare Faraday.new (which would reopen the SSRF/DNS-rebinding hole, e.g.
      #     token_url -> 169.254.169.254).
      #   - The access_token and client_secret are NEVER logged, echoed, or placed
      #     in an exception message; the BaseBroker rescue logs e.class only and
      #     degrades to the base credential.
      #
      # CACHING: the access_token is cached (BrokerCache) for (expires_in - skew)
      # seconds keyed on a digest of (source id, "oauth2", token_url, scope) plus a
      # NON-reversible fingerprint of the client secret, so a rotated client secret
      # naturally invalidates the cache and a swarm at expiry collapses onto ~one
      # token request (singleflight, no sleep).
      class Oauth2ClientCredentialsBroker < BaseBroker
        GRANT_TYPE = "client_credentials"
        DEFAULT_SKEW_SECONDS = 60
        DEFAULT_CLIENT_AUTH = "basic"
        FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"
        # Upper bound on a cached access-token lifetime. A token endpoint returning an
        # absurd expires_in must not pin a stale bearer in Redis for years (a revoked
        # token would keep being served); cap it. Mirrors the sibling brokers' caps
        # (AwsStsBroker::MAX_DURATION_SECONDS, the S3 presigner max).
        MAX_TOKEN_TTL_SECONDS = 86_400

        protected

        def acquire!(data_source:, base_credential:, config:)
          token_url = cfg(config, :token_url).to_s
          return base_credential if token_url.blank?

          client_id = base_credential&.decrypted_api_key
          client_secret = base_credential&.decrypted_api_secret
          # Without a client_id there is nothing to exchange; degrade to base.
          return base_credential if client_id.blank?

          scope = cfg(config, :scope).to_s
          audience = cfg(config, :audience).to_s
          client_auth = normalize_client_auth(cfg(config, :client_auth))
          skew = (cfg(config, :skew_seconds) || DEFAULT_SKEW_SECONDS).to_i

          key = cache_key(
            data_source: data_source,
            token_url: token_url,
            scope: scope,
            audience: audience,
            client_id: client_id,
            client_secret: client_secret
          )

          material = BrokerCache.fetch(key) do
            access_token, expires_in = request_token(
              data_source: data_source,
              token_url: token_url,
              client_id: client_id,
              client_secret: client_secret,
              scope: scope,
              audience: audience,
              client_auth: client_auth
            )
            next { material: nil, ttl_seconds: 0 } if access_token.blank?

            expires_at = expires_in&.positive? ? Time.current + expires_in : nil
            audit_log(data_source, "acquired", expires_at: iso(expires_at))
            {
              # Stash the absolute expiry IN the cached material (a harmless
              # pass-through field — BrokeredCredential reads the token via "token",
              # never "expires_at") so #expired? is meaningful on a cache HIT too.
              material: { "token" => access_token, "expires_at" => iso(expires_at) }.compact,
              ttl_seconds: lease_seconds(expires_at: expires_at, skew_seconds: skew)
            }
          end

          return base_credential if material.nil? || material["token"].blank?

          BrokeredCredential.new(material, expires_at: material["expires_at"])
        end

        # Canonical registry token (matches Registry::BROKERS key).
        def broker_type
          "oauth2_client_credentials"
        end

        private

        # POST the token endpoint through the SSRF-guarded connection. Returns
        # [access_token, expires_in_seconds_or_nil]. Raises on transport/parse
        # failure — the public #acquire (BaseBroker) catches and degrades to base.
        # NEVER logs the token, client_secret, or response body.
        def request_token(data_source:, token_url:, client_id:, client_secret:,
                          scope:, audience:, client_auth:)
          form = { "grant_type" => GRANT_TYPE }
          form["scope"] = scope if scope.present?
          form["audience"] = audience if audience.present?

          headers = {
            "Content-Type" => FORM_CONTENT_TYPE,
            "Accept" => "application/json"
          }

          if client_auth == "body"
            form["client_id"] = client_id
            form["client_secret"] = client_secret
          else
            headers["Authorization"] = basic_auth_header(client_id, client_secret)
          end

          # max_redirects: 0 — a token endpoint must not redirect; never follow a 3xx
          # (which, in "body" client_auth mode, could replay client_secret to the
          # redirect target host). A 3xx response then parses as non-2xx => degrade.
          conn = broker_http_connection(token_url, data_source: data_source, max_redirects: 0)
          # Dispatch against the ABSOLUTE token_url so SsrfGuardMiddleware re-validates
          # the exact target per request and validate_redirect! re-pins every hop.
          response = conn.run_request(:post, token_url, URI.encode_www_form(form), headers)
          parse_token_response(response)
        end

        # Parse the token endpoint's JSON. Returns [access_token, expires_in].
        # A non-2xx, non-JSON, or token-less body yields [nil, nil] (caller degrades)
        # WITHOUT surfacing any response content (which could echo a secret).
        def parse_token_response(response)
          return [nil, nil] unless response&.respond_to?(:status)
          return [nil, nil] unless (200..299).cover?(response.status)

          body = response.body
          parsed = body.is_a?(Hash) ? body : safe_parse_json(body)
          return [nil, nil] unless parsed.is_a?(Hash)

          token = parsed["access_token"] || parsed[:access_token]
          expires_in = (parsed["expires_in"] || parsed[:expires_in]).to_i
          expires_in = MAX_TOKEN_TTL_SECONDS if expires_in > MAX_TOKEN_TTL_SECONDS
          [token.presence, expires_in.positive? ? expires_in : nil]
        end

        def safe_parse_json(body)
          str = body.to_s
          return nil if str.empty?

          JSON.parse(str)
        rescue JSON::ParserError
          nil
        end

        def basic_auth_header(client_id, client_secret)
          raw = "#{client_id}:#{client_secret}"
          "Basic #{Base64.strict_encode64(raw)}"
        end

        def normalize_client_auth(value)
          v = value.to_s.strip.downcase
          v == "body" ? "body" : DEFAULT_CLIENT_AUTH
        end

        # Stable, NON-secret cache key. Mixes a SHA256 fingerprint of the client
        # secret (so rotation busts the cache) without storing/logging the secret.
        def cache_key(data_source:, token_url:, scope:, audience:, client_id:, client_secret:)
          source_id = data_source.respond_to?(:id) ? data_source.id : "unknown"
          fingerprint = Digest::SHA256.hexdigest(
            "#{client_id}:#{client_secret}:#{token_url}:#{scope}:#{audience}"
          )
          "oauth2:#{source_id}:#{fingerprint}"
        end

        def iso(time)
          time&.utc&.iso8601
        end
      end
    end
  end
end
