# frozen_string_literal: true

require "aws-sdk-core"

module Ai
  module DataSources
    module Credentials
      # Dynamic credential broker: exchanges the BASE credential's long-lived AWS
      # keys for SHORT-LIVED STS credentials via AssumeRole, just before the signed
      # fetch. The returned BrokeredCredential exposes access_key_id /
      # secret_access_key / session_token so the existing Sigv4Signer can sign with
      # the temporary role session unchanged.
      #
      # WHY: a data source configured for AWS SigV4 (e.g. a private execute-api / S3
      # endpoint) should NOT sign with a static IAM user key. Instead it stores a
      # low-privilege base key whose only power is sts:AssumeRole into a scoped role;
      # the broker mints a 1-hour (configurable) session per the lease, caching it in
      # Redis so STS is not hit on every request.
      #
      # CONFIG (data_source.auth_config["broker"], all NON-secret):
      #   { "type" => "aws_sts",
      #     "role_arn"         => "arn:aws:iam::123456789012:role/powernode-reader", # required
      #     "session_name"     => "powernode-ds",       # optional (RoleSessionName)
      #     "duration_seconds" => 3600,                  # optional (900..43200)
      #     "external_id"      => "...",                 # optional (confused-deputy guard)
      #     "region"           => "us-east-1",           # optional (STS client region)
      #     "skew_seconds"     => 60 }                    # optional (default 60)
      #
      # BASE SECRETS (read off base_credential, NEVER off config):
      #   decrypted_api_key    => AWS access_key_id   used to CALL AssumeRole
      #   decrypted_api_secret => AWS secret_access_key used to CALL AssumeRole
      #
      # SECURITY:
      #   - No token/secret/session_token is ever logged. The STS SDK call hits the
      #     fixed AWS STS endpoint; a config-supplied endpoint override is NOT
      #     honored (that would reintroduce SSRF). Failures degrade to base via the
      #     BaseBroker#acquire rescue (logs e.class only).
      class AwsStsBroker < BaseBroker
        DEFAULT_SESSION_NAME = "powernode-ds"
        DEFAULT_DURATION_SECONDS = 3600
        DEFAULT_SKEW_SECONDS = 60

        # AWS STS hard bounds on AssumeRole DurationSeconds (15 min .. 12 h).
        MIN_DURATION_SECONDS = 900
        MAX_DURATION_SECONDS = 43_200

        protected

        # Mint a short-lived STS session via AssumeRole using the base credential's
        # AWS keys. Returns a BrokeredCredential, or base_credential to no-op when
        # the broker is misconfigured (no role_arn / no base keys).
        def acquire!(data_source:, base_credential:, config:)
          role_arn = cfg(config, :role_arn)
          return base_credential if role_arn.blank?

          access_key_id = base_credential&.decrypted_api_key
          secret_access_key = base_credential&.decrypted_api_secret
          if access_key_id.blank? || secret_access_key.blank?
            audit_log(data_source, "skipped", reason: "missing_base_aws_keys")
            return base_credential
          end

          skew = (cfg(config, :skew_seconds) || DEFAULT_SKEW_SECONDS).to_i

          material = BrokerCache.fetch(
            cache_key_for(data_source, role_arn, access_key_id, secret_access_key)
          ) do
            assume_and_wrap(
              data_source: data_source,
              access_key_id: access_key_id,
              secret_access_key: secret_access_key,
              role_arn: role_arn,
              config: config,
              skew: skew
            )
          end

          return base_credential if material.nil?

          BrokeredCredential.new(material, expires_at: expiry_from(material))
        end

        # Canonical registry token.
        def broker_type
          "aws_sts"
        end

        private

        # Perform the AssumeRole exchange and shape the BrokerCache block result
        # ({ material:, ttl_seconds: }). Runs only on a cache MISS. MAY raise — the
        # public #acquire (BaseBroker) catches and degrades to base.
        def assume_and_wrap(data_source:, access_key_id:, secret_access_key:, role_arn:, config:, skew:)
          creds = assume_role(
            access_key_id: access_key_id,
            secret_access_key: secret_access_key,
            role_arn: role_arn,
            config: config
          )

          expires_at = creds.expiration # Time (absolute, UTC) from the SDK
          material = sts_material(creds)

          audit_log(
            data_source, "acquired",
            expires_at: (expires_at&.utc&.iso8601 || "none")
          )

          {
            material: material,
            ttl_seconds: lease_seconds(expires_at: expires_at, skew_seconds: skew)
          }
        end

        # Call AWS STS AssumeRole with the BASE credential's keys. The STS client
        # targets the fixed AWS STS endpoint (optionally regionalized via config);
        # an arbitrary endpoint override is deliberately NOT accepted.
        #
        # @return [Aws::STS::Types::Credentials] (access_key_id, secret_access_key,
        #   session_token, expiration)
        def assume_role(access_key_id:, secret_access_key:, role_arn:, config:)
          resp = sts_client(
            access_key_id: access_key_id,
            secret_access_key: secret_access_key,
            config: config
          ).assume_role(assume_role_params(role_arn: role_arn, config: config))

          resp.credentials
        end

        # Build the AssumeRole request params from NON-secret config knobs.
        def assume_role_params(role_arn:, config:)
          duration = clamp_duration(cfg(config, :duration_seconds))
          params = {
            role_arn: role_arn,
            role_session_name: (cfg(config, :session_name) || DEFAULT_SESSION_NAME).to_s,
            duration_seconds: duration
          }
          external_id = cfg(config, :external_id)
          params[:external_id] = external_id.to_s if external_id.present?
          params
        end

        # Construct an STS client authenticated with the base credential's keys.
        # Region is honored (STS is regionalizable) but ENDPOINT is NOT taken from
        # config — only the fixed/regional AWS STS endpoint is used.
        def sts_client(access_key_id:, secret_access_key:, config:)
          opts = {
            access_key_id: access_key_id,
            secret_access_key: secret_access_key
          }
          region = cfg(config, :region)
          opts[:region] = region.to_s if region.present?
          # STS is a global service; supply a default region when none configured so
          # the SDK does not raise Aws::Errors::MissingRegionError.
          opts[:region] ||= "us-east-1"
          Aws::STS::Client.new(opts)
        end

        # Shape STS credentials into the signer material Hash. Keys match the
        # BrokeredCredential / Sigv4Signer spelling:
        #   access_key_id  -> #decrypted_api_key
        #   secret_access_key -> #decrypted_api_secret
        #   session_token  -> credential["session_token"]
        # A non-secret "expiration" ISO8601 string is carried so a cache HIT (which
        # only returns material) can still reconstruct the lease expiry.
        def sts_material(creds)
          {
            "access_key_id" => creds.access_key_id,
            "secret_access_key" => creds.secret_access_key,
            "session_token" => creds.session_token,
            "expiration" => creds.expiration&.utc&.iso8601
          }
        end

        # Recover the absolute expiry from cached/fresh material (string keys after a
        # Redis round-trip; BrokeredCredential#coerce_time parses the ISO8601 too,
        # but we pass a Time for fresh material symmetry).
        def expiry_from(material)
          raw = material["expiration"] || material[:expiration]
          return nil if raw.blank?

          Time.zone ? Time.zone.parse(raw.to_s) : Time.parse(raw.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        # Clamp the requested DurationSeconds into the STS-allowed window; default
        # when unset/invalid. (STS rejects out-of-range durations.)
        def clamp_duration(raw)
          requested = Integer(raw, exception: false) || DEFAULT_DURATION_SECONDS
          requested = DEFAULT_DURATION_SECONDS unless requested.positive?
          requested.clamp(MIN_DURATION_SECONDS, MAX_DURATION_SECONDS)
        end

        # Stable cache key: broker type + source id + role + a non-reversible
        # fingerprint of the base key (so rotating the base key invalidates the
        # cached session). The base key itself is NEVER stored in the key.
        def cache_key_for(data_source, role_arn, access_key_id, secret_access_key)
          source_id = data_source.respond_to?(:id) ? data_source.id : "unknown"
          # Fingerprint BOTH base keys so rotating either (id and/or secret)
          # invalidates the cached session. Non-reversible; the keys are never stored.
          fingerprint = Digest::SHA256.hexdigest("#{access_key_id}:#{secret_access_key}")[0, 16]
          "aws_sts:#{source_id}:#{Digest::SHA256.hexdigest(role_arn.to_s)[0, 16]}:#{fingerprint}"
        end
      end
    end
  end
end
