# frozen_string_literal: true

require "aws-sdk-core"

module Ai
  module DataSources
    module Credentials
      # KEYLESS workload-identity broker: exchanges an OIDC/JWT web-identity token
      # for SHORT-LIVED AWS STS credentials via AssumeRoleWithWebIdentity, just
      # before the signed fetch. NO static AWS keys are required (that is the point —
      # the workload proves its identity with a federated OIDC token instead of a
      # long-lived IAM secret). The returned BrokeredCredential exposes
      # access_key_id / secret_access_key / session_token, identical shape to
      # AwsStsBroker, so the existing Sigv4Signer signs the temporary session
      # unchanged.
      #
      # Subclasses AwsStsBroker to reuse the STS material shaping, expiry recovery,
      # duration clamping, and lease/cache plumbing — only the token sourcing, the
      # STS exchange (no static keys), and the cache key differ.
      #
      # WHERE THE OIDC TOKEN COMES FROM (checked in this order; first present wins):
      #   1. config "web_identity_token" — the raw JWT inline (e.g. injected by the
      #      workload runtime / a sidecar). Treated as a NON-secret config knob here
      #      only in the sense that it is short-lived and federation-scoped; it is
      #      NEVER logged.
      #   2. config "token_file" — an absolute path to the projected token on disk
      #      (the canonical IRSA / EKS Pod Identity / GitHub-OIDC pattern:
      #      AWS_WEB_IDENTITY_TOKEN_FILE). Read at acquisition time.
      #   3. config "token_url" — an HTTP endpoint that returns the token in its
      #      body (e.g. a local OIDC token-exchange / IMDS-style minter). This URL is
      #      user-config-derived, so it MUST be fetched through the SSRF-guarded
      #      connection (#broker_http_connection) — a bare Faraday.new would
      #      reintroduce the SSRF/DNS-rebinding hole (token_url -> 169.254.169.254).
      #
      # CONFIG (data_source.auth_config["broker"], all NON-secret knobs):
      #   { "type" => "aws_sts_web_identity",
      #     "role_arn"            => "arn:aws:iam::123456789012:role/powernode-irsa", # required
      #     "session_name"        => "powernode-ds",  # optional (RoleSessionName)
      #     "duration_seconds"    => 3600,             # optional (900..43200)
      #     "skew_seconds"        => 60,               # optional (default 60)
      #     "region"              => "us-east-1",      # optional (STS client region)
      #     # exactly one token source:
      #     "web_identity_token"  => "<jwt>",          # OR
      #     "token_file"          => "/var/run/secrets/.../token", # OR
      #     "token_url"           => "https://idp.internal/token", # SSRF-guarded
      #     "token_request_method" => "get" }           # optional (default GET)
      #
      # base_credential is IGNORED for the exchange (keyless). It is still passed
      # through and returned unchanged on any no-op/degrade path so the signer layer
      # always receives a usable credential.
      #
      # SECURITY:
      #   - The OIDC token, the STS session token, and the STS secret are NEVER
      #     logged. token_url fetches go through the SSRF guard. The STS SDK call
      #     hits the fixed/regional AWS STS endpoint; no config endpoint override.
      #     Failures degrade to base via BaseBroker#acquire (logs e.class only).
      class AwsStsWebIdentityBroker < AwsStsBroker
        DEFAULT_TOKEN_REQUEST_METHOD = :get

        protected

        # Mint a short-lived STS session via AssumeRoleWithWebIdentity. Returns a
        # BrokeredCredential, or base_credential to no-op when misconfigured (no
        # role_arn, or no resolvable OIDC token). MAY raise — BaseBroker#acquire
        # catches and degrades.
        def acquire!(data_source:, base_credential:, config:)
          role_arn = cfg(config, :role_arn)
          return base_credential if role_arn.blank?

          # Cache key is independent of the (volatile) token value — it keys on the
          # role + token SOURCE so two requests share one STS session. The block
          # (run only on a miss) resolves the token freshly so a rotated token is
          # picked up on the next acquisition.
          skew = (cfg(config, :skew_seconds) || DEFAULT_SKEW_SECONDS).to_i

          material = BrokerCache.fetch(
            cache_key_for_web_identity(data_source, role_arn, config)
          ) do
            web_identity_block(data_source: data_source, role_arn: role_arn, config: config, skew: skew)
          end

          return base_credential if material.nil?

          BrokeredCredential.new(material, expires_at: expiry_from(material))
        end

        # Canonical registry token.
        def broker_type
          "aws_sts_web_identity"
        end

        private

        # BrokerCache block: resolve the OIDC token, perform the keyless exchange,
        # and shape { material:, ttl_seconds: }. Runs only on a cache MISS.
        def web_identity_block(data_source:, role_arn:, config:, skew:)
          token = resolve_web_identity_token(data_source: data_source, config: config)
          if token.blank?
            audit_log(data_source, "skipped", reason: "missing_web_identity_token")
            return { material: nil, ttl_seconds: 0 }
          end

          creds = assume_role_with_web_identity(
            role_arn: role_arn,
            web_identity_token: token,
            config: config
          )

          expires_at = creds.expiration
          audit_log(
            data_source, "acquired",
            expires_at: (expires_at&.utc&.iso8601 || "none")
          )

          {
            material: sts_material(creds),
            ttl_seconds: lease_seconds(expires_at: expires_at, skew_seconds: skew)
          }
        end

        # Call AWS STS AssumeRoleWithWebIdentity with the OIDC token. NO static AWS
        # keys: the STS client is UNAUTHENTICATED (this STS API is the federation
        # entry point — the web_identity_token IS the proof of identity). Region is
        # honored; endpoint override is NOT.
        #
        # @return [Aws::STS::Types::Credentials]
        def assume_role_with_web_identity(role_arn:, web_identity_token:, config:)
          params = {
            role_arn: role_arn,
            role_session_name: (cfg(config, :session_name) || DEFAULT_SESSION_NAME).to_s,
            web_identity_token: web_identity_token,
            duration_seconds: clamp_duration(cfg(config, :duration_seconds))
          }
          web_identity_sts_client(config).assume_role_with_web_identity(params).credentials
        end

        # Unauthenticated STS client (no signature; the web identity token carries
        # the auth). `credentials: false` tells the SDK not to look for ambient
        # credentials. Region honored, endpoint NOT overridable from config.
        def web_identity_sts_client(config)
          opts = { credentials: false }
          region = cfg(config, :region)
          opts[:region] = region.present? ? region.to_s : "us-east-1"
          Aws::STS::Client.new(opts)
        end

        # Resolve the OIDC token from the configured source (inline > file > URL).
        # Returns the raw token String, or nil when none is resolvable.
        def resolve_web_identity_token(data_source:, config:)
          inline = cfg(config, :web_identity_token)
          return inline.to_s if inline.present?

          file = cfg(config, :token_file)
          return read_token_file(file) if file.present?

          url = cfg(config, :token_url)
          return fetch_token_url(url, data_source: data_source, config: config) if url.present?

          nil
        end

        # Read a projected token off disk (IRSA / EKS Pod Identity pattern). Failures
        # bubble to BaseBroker#acquire which degrades to base. The token VALUE is
        # never logged.
        def read_token_file(path)
          token = File.read(path.to_s).to_s.strip
          token.presence
        end

        # Fetch the OIDC token from a config-supplied URL through the SSRF-guarded
        # connection. MUST dispatch against the ABSOLUTE url so SsrfGuardMiddleware
        # re-validates the exact target (and validate_redirect! re-pins every hop) —
        # never a bare Faraday.new. The response body is the raw token.
        def fetch_token_url(url, data_source:, config:)
          conn = broker_http_connection(url, data_source: data_source)
          method = token_request_method(config)
          response = conn.run_request(method, url, nil, nil)
          return nil unless response.respond_to?(:success?) && response.success?

          response.body.to_s.strip.presence
        end

        # HTTP method for the token_url fetch (default GET; some minters want POST).
        def token_request_method(config)
          raw = cfg(config, :token_request_method)
          return DEFAULT_TOKEN_REQUEST_METHOD if raw.blank?

          %i[get post].include?(raw.to_s.downcase.to_sym) ? raw.to_s.downcase.to_sym : DEFAULT_TOKEN_REQUEST_METHOD
        end

        # Cache key for the keyless flow: broker type + source id + role + a digest
        # of the token SOURCE descriptor (not the token value). Distinct sources for
        # the same role get distinct cache slots; the token itself never appears.
        def cache_key_for_web_identity(data_source, role_arn, config)
          source_id = data_source.respond_to?(:id) ? data_source.id : "unknown"
          descriptor = [
            cfg(config, :token_url),
            cfg(config, :token_file),
            (cfg(config, :web_identity_token).present? ? "inline" : nil)
          ].compact.join("|")
          role_fp = Digest::SHA256.hexdigest(role_arn.to_s)[0, 16]
          src_fp = Digest::SHA256.hexdigest(descriptor)[0, 16]
          "aws_sts_web_identity:#{source_id}:#{role_fp}:#{src_fp}"
        end
      end
    end
  end
end
