# frozen_string_literal: true

require "digest"

module Ai
  module DataSources
    module Credentials
      # Broker that reads a Vault DYNAMIC secrets engine path and hands the signer
      # layer a SHORT-LIVED credential minted on demand by Vault.
      #
      # WHAT IT EXCHANGES: a static/Vault BASE credential is irrelevant here as a
      # *secret* (the dynamic engine mints fresh creds itself) — instead the broker
      # reads a Vault dynamic mount path configured per data source, e.g.
      #   config["vault_path"] = "database/creds/readonly-role"   (DB engine)
      #   config["vault_path"] = "aws/creds/s3-reader"            (AWS engine)
      # Vault returns short-lived material plus a lease_duration. We map that into a
      # BrokeredCredential satisfying the signer contract and cache it (via
      # BrokerCache) for lease - skew seconds, so the dynamic engine is not hit on
      # every fetch and a swarm at expiry collapses onto ~one read (singleflight).
      #
      # ENGINE-SHAPE TOLERANCE: dynamic engines name their fields differently. The
      # DB engine returns {username, password}; the AWS engine returns
      # {access_key, secret_key, security_token}. We populate BrokeredCredential
      # material with BOTH the generic spellings AND the session-token key the
      # Sigv4Signer reads (credential["session_token"]), so either engine's lease
      # is consumable by the existing signers UNCHANGED.
      #
      # VAULT REACH: reuses the SAME platform Vault path the credential provider
      # uses (::Security::VaultClient.read_secret) rather than instantiating a new
      # client. We pass cache: false so VaultClient's generic 5-minute KV cache does
      # not pin a just-minted dynamic lease past its real TTL — BrokerCache owns the
      # lease-correct caching here. Account scoping: the dynamic read itself is keyed
      # by the configured mount path, but we REQUIRE data_source.account&.id to be
      # present (mirrors the provider's account-scoped contract) and fold it into the
      # cache key so leases never cross account boundaries in Redis.
      #
      # SECURITY: the minted username/password/keys are NEVER logged. Only the broker
      # type, source slug, outcome, and lease expiry appear in the audit line. On ANY
      # failure (Vault sealed/unavailable, missing path, missing account, malformed
      # response) the broker degrades to the BASE credential via BaseBroker#acquire —
      # the fetch pipeline never crashes on a brokering fault.
      class VaultDynamicBroker < BaseBroker
        # Safety skew default (seconds): drop the cached lease this far before Vault's
        # advertised expiry so we never sign with a just-expired dynamic credential.
        DEFAULT_SKEW_SECONDS = 30

        protected

        # @param data_source [Ai::DataSource]
        # @param base_credential [#decrypted_api_key, ...] resolved static/Vault cred,
        #   or nil. Returned UNCHANGED whenever brokering cannot proceed (no path, no
        #   account, empty Vault response) so the fetch degrades safely.
        # @param config [Hash] auth_config["broker"] — NON-secret knobs. Reads:
        #   "vault_path" (required), "skew_seconds" (default 30),
        #   "lease_seconds"/"ttl" (fallback lease when Vault omits lease_duration).
        # @return [BrokeredCredential, #decrypted_api_key] the dynamic lease, or base.
        def acquire!(data_source:, base_credential:, config:)
          vault_path = cfg(config, :vault_path, :path)
          if vault_path.blank?
            audit_log(data_source, "skipped", reason: "no_vault_path")
            return base_credential
          end

          account_id = data_source.account&.id
          if account_id.blank?
            # The platform Vault integration is account-scoped; without an account we
            # cannot safely attribute or cache the lease. Degrade to base.
            audit_log(data_source, "skipped", reason: "no_account")
            return base_credential
          end

          skew = (cfg(config, :skew_seconds) || DEFAULT_SKEW_SECONDS).to_i
          cache_key = cache_key_for(data_source, vault_path, account_id, base_credential)

          material = Ai::DataSources::Credentials::BrokerCache.fetch(cache_key) do
            read_dynamic_lease(vault_path: vault_path, skew_seconds: skew)
          end

          if material.blank?
            audit_log(data_source, "skipped", reason: "empty_lease")
            return base_credential
          end

          expires_at = expires_at_from_material(material)
          audit_log(data_source, "acquired", expires_at: expires_at&.utc&.iso8601 || "none")
          Ai::DataSources::Credentials::BrokeredCredential.new(material, expires_at: expires_at)
        end

        # Canonical registry token (matches Registry::BROKERS key) for audit lines.
        def broker_type
          "vault_dynamic"
        end

        private

        # MISS-path: read the dynamic mount and shape the result into the
        # { material:, ttl_seconds: } contract BrokerCache expects. Runs only on a
        # cache miss (or fail-open). MAY raise — BrokerCache absorbs cache faults and
        # BaseBroker#acquire absorbs everything else into a base-credential degrade.
        #
        # @return [Hash{Symbol=>Object}] { material: Hash, ttl_seconds: Integer }.
        #   ttl_seconds <= 0 (unknown lease) signals BrokerCache to return the
        #   material UNCACHED, so the next fetch re-reads a fresh lease.
        def read_dynamic_lease(vault_path:, skew_seconds:)
          # Reuse the platform Vault path (class-level delegate to the singleton).
          # cache: false so a short-lived dynamic lease is not pinned by VaultClient's
          # generic 5-minute KV cache — BrokerCache owns the lease-correct TTL.
          secret = ::Security::VaultClient.read_secret(vault_path, cache: false)
          data = secret.is_a?(Hash) ? secret : {}
          return { material: nil, ttl_seconds: 0 } if data.empty?

          material = build_material(data)
          return { material: nil, ttl_seconds: 0 } if material.empty?

          lease = lease_duration_from(data)
          # Embed the absolute expiry in the cached material so a later cache HIT can
          # reconstruct #expires_at for the BrokeredCredential (BrokerCache stores
          # only the material Hash, not the lease metadata).
          if lease&.positive?
            expires_at = Time.current + lease.seconds
            material["expires_at"] = expires_at.utc.iso8601
            ttl = Ai::DataSources::Credentials::BrokerCache.ttl_with_skew(
              expires_at: expires_at, skew_seconds: skew_seconds
            )
          else
            # No advertised lease: return the material but DO NOT cache it (ttl<=0).
            ttl = 0
          end

          { material: material, ttl_seconds: ttl }
        end

        # Map a Vault dynamic-engine response into BrokeredCredential material,
        # tolerating symbol OR string keys (the Vault gem returns symbol keys; a
        # cache HIT round-trips as string keys). Populates BOTH generic credential
        # spellings AND the AWS session-token key the Sigv4Signer reads. Only present
        # values are copied — absent fields are left out so BrokeredCredential's
        # spelling-fallback chooses correctly.
        #
        # DB engine    => {username, password}
        # AWS engine   => {access_key, secret_key, security_token}
        def build_material(data)
          material = {}

          # Primary key half: AWS access_key (=> access_key_id), else DB username.
          access_key = dig_any(data, :access_key, :access_key_id)
          username   = dig_any(data, :username, :user)
          if access_key.present?
            material["access_key_id"] = access_key
          elsif username.present?
            # DB dynamic creds: username is the primary identifier. Signers that read
            # decrypted_api_key see it via the api_key/access_key_id/token/key chain,
            # so expose it under "api_key" and keep the explicit "username" too.
            material["api_key"] = username
            material["username"] = username
          end

          # Secret half: AWS secret_key (=> secret_access_key), else DB password.
          secret_key = dig_any(data, :secret_key, :secret_access_key)
          password   = dig_any(data, :password, :pass)
          if secret_key.present?
            material["secret_access_key"] = secret_key
          elsif password.present?
            material["api_secret"] = password
            material["password"] = password
          end

          # AWS STS session token (the AWS dynamic engine names it security_token;
          # newer responses use session_token). Sigv4Signer reads ["session_token"],
          # so normalize to that key while keeping the original for completeness.
          session_token = dig_any(data, :security_token, :session_token)
          if session_token.present?
            material["session_token"] = session_token
            material["security_token"] = session_token
          end

          material
        end

        # Vault advertises the dynamic lease on the response envelope, but the
        # platform's VaultClient.read_secret returns only the data Hash (stripping
        # lease metadata). Some engines/setups also surface the lease inside the data
        # payload — honor that when present, else nil (caller treats nil as
        # "uncacheable, re-read each time"). Tolerates symbol/string keys.
        def lease_duration_from(data)
          raw = dig_any(data, :lease_duration, :ttl, :lease_seconds)
          val = raw.to_i
          val.positive? ? val : nil
        rescue StandardError
          nil
        end

        # Reconstruct the absolute expiry (a Time) for the BrokeredCredential.
        # Prefers the embedded "expires_at" (set on the miss path as an ISO8601
        # String so it survives the JSON round-trip of a cache HIT) and coerces it
        # back to a Time; falls back to deriving from a lease field if only that is
        # present. Returns nil when neither is available (no-expiry lease). The
        # absolute expiry is Vault's real expiry — the safety skew is applied to the
        # CACHE TTL, not here, and BrokeredCredential#expired? re-applies skew at
        # read time.
        def expires_at_from_material(material)
          embedded = dig_any(material, :expires_at)
          if embedded.present?
            return embedded if embedded.is_a?(Time)

            parsed = parse_time(embedded)
            return parsed if parsed
          end

          lease = lease_duration_from(material)
          lease&.positive? ? (Time.current + lease.seconds) : nil
        end

        # Parse an ISO8601 (or Vault-stringified) timestamp into a Time, returning
        # nil on a malformed value rather than raising.
        def parse_time(value)
          Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        # First present value among +keys+, tolerating String OR Symbol spellings.
        # Blank-but-present values are skipped so a later spelling can win.
        def dig_any(hash, *keys)
          return nil unless hash.is_a?(Hash)

          keys.each do |key|
            [key, key.to_s, key.to_sym].uniq.each do |variant|
              value = hash[variant]
              return value if value.respond_to?(:empty?) ? !value.empty? : !value.nil?
            end
          end
          nil
        end

        # Stable, NON-SECRET cache key. Folds the broker type, source id, mount path,
        # account id, and a SHORT fingerprint of the base credential so a rotated base
        # secret busts the cache without ever putting secret bytes in the key. The
        # fingerprint is a truncated SHA-256 of the base key/secret — one-way, not
        # reversible, and never logged (only the namespaced key is, by BrokerCache).
        def cache_key_for(data_source, vault_path, account_id, base_credential)
          fingerprint = base_credential_fingerprint(base_credential)
          raw = ["vault_dynamic", data_source&.id, account_id, vault_path, fingerprint].join(":")
          Digest::SHA256.hexdigest(raw)
        end

        # One-way fingerprint of the base credential's secret material so rotation
        # invalidates the cache. Returns "none" when there is no base secret. NEVER
        # returns or logs the raw secret.
        def base_credential_fingerprint(base_credential)
          return "none" unless base_credential

          key = safe_reader(base_credential, :decrypted_api_key)
          secret = safe_reader(base_credential, :decrypted_api_secret)
          return "none" if key.blank? && secret.blank?

          Digest::SHA256.hexdigest("#{key}:#{secret}")[0, 16]
        rescue StandardError
          "none"
        end

        def safe_reader(obj, method)
          obj.respond_to?(method) ? obj.public_send(method) : nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
