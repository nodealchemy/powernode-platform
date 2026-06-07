# frozen_string_literal: true

require "openssl"
require "base64"
require "digest"
require "uri"

module Ai
  module DataSources
    module Credentials
      # Exchanges the resolved base credential for a SHORT-LIVED, self-authenticating
      # PRESIGNED URL — a URL whose query string carries the signature, so the fetch
      # needs no Authorization header and no separate signing step. Two providers:
      #
      #   (a) "s3" (DEFAULT) — Aws::S3::Presigner (aws-sdk-s3, bundled). Uses the
      #       BASE credential's AWS keys (#decrypted_api_key => access_key_id,
      #       #decrypted_api_secret => secret_access_key, optional ["session_token"])
      #       to presign a GET on get_object(bucket:, key:, expires_in:). The SDK
      #       targets the FIXED AWS S3 endpoint for the region; we deliberately do
      #       NOT honor a config-supplied endpoint override (that would reopen the
      #       SSRF hole the data-source pipeline closed — a presigned URL is fetched
      #       later through the SSRF-guarded connection, but only fixed-endpoint AWS
      #       signing is allowed here).
      #
      #   (b) "azure_sas" — generate an Azure Blob *service SAS* token by HMAC-SHA256
      #       (OpenSSL, no SDK) over the canonical string-to-sign, using the storage
      #       ACCOUNT KEY from the base credential (#decrypted_api_secret, base64).
      #       The account name comes from the base credential's #decrypted_api_key
      #       (or config "account_name"); the blob URL is reconstructed and the SAS
      #       appended as "?<sas>". Canonicalization is implemented inline so it is
      #       deterministic and unit-testable given fixed inputs + a fixed clock.
      #
      # RESULT: a BrokeredCredential carrying the URL via #presigned_url (and
      # #["presigned_url"]). decrypted_api_key is intentionally nil — the URL itself
      # carries the auth, and QueryService's honor-hook dispatches straight to it and
      # SKIPS signing. The URL is cached (BrokerCache) for (expires_in - skew) so a
      # swarm reuses one signed URL instead of re-presigning per request.
      #
      # SECURITY (mirrors BaseBroker / sign_request! discipline):
      #   - NEVER log/echo the account key, secret, session token, or the signed URL
      #     (the SAS/signature lives in its query string). Audit lines are non-secret
      #     only (provider, source slug, outcome, expiry).
      #   - No outbound HTTP is made here: S3 presigning is a local HMAC over a fixed
      #     AWS endpoint, and the Azure SAS is a local HMAC. So there is no
      #     config-supplied URL to dispatch and no SSRF surface in acquisition. (The
      #     resulting presigned URL is fetched LATER by QueryService through the
      #     SSRF-guarded connection, where its host is validated.)
      #   - Degrades to base on any failure via the BaseBroker#acquire rescue.
      class PresignedUrlBroker < BaseBroker
        # Default presign lifetime (seconds) when config omits expires_in. Matches
        # the data-source signed-URL convention (15 minutes).
        DEFAULT_EXPIRES_IN = 900

        # AWS S3 hard cap for a SigV4 presigned URL lifetime (7 days). We clamp to
        # this so an over-large config value cannot produce an invalid presign.
        S3_MAX_EXPIRES_IN = 604_800

        # Azure service SAS signed version. Pinned so the string-to-sign field order
        # is deterministic and matches what the service validates.
        AZURE_SAS_VERSION = "2021-08-06"

        # Azure SAS signed resource for a single blob.
        AZURE_RESOURCE_BLOB = "b"

        protected

        def acquire!(data_source:, base_credential:, config:)
          provider = cfg(config, :provider).to_s.strip.downcase
          provider = "s3" if provider.empty?

          case provider
          when "s3"
            acquire_s3(data_source: data_source, base_credential: base_credential, config: config)
          when "azure_sas"
            acquire_azure_sas(data_source: data_source, base_credential: base_credential, config: config)
          else
            # Unknown provider: degrade to base rather than guessing.
            audit_log(data_source, "skipped", reason: "unknown_provider")
            base_credential
          end
        end

        # Canonical registry token.
        def broker_type
          "presigned_url"
        end

        private

        # --------------------------------------------------------------------
        # (a) AWS S3 presigned GET
        # --------------------------------------------------------------------

        def acquire_s3(data_source:, base_credential:, config:)
          bucket = cfg(config, :bucket).to_s
          object_key = cfg(config, :object_key, :key).to_s
          if bucket.empty? || object_key.empty?
            audit_log(data_source, "skipped", reason: "missing_bucket_or_key")
            return base_credential
          end

          region = cfg(config, :region).to_s
          if region.empty?
            audit_log(data_source, "skipped", reason: "missing_region")
            return base_credential
          end

          access_key_id, secret_access_key, session_token = aws_base_keys(base_credential)
          if access_key_id.to_s.empty? || secret_access_key.to_s.empty?
            audit_log(data_source, "skipped", reason: "missing_base_aws_keys")
            return base_credential
          end

          expires_in = clamp_expires(cfg(config, :expires_in), max: S3_MAX_EXPIRES_IN)
          skew = skew_seconds(config)
          expires_at = Time.current + expires_in

          material = BrokerCache.fetch(
            cache_key_for(data_source, "s3", access_key_id, "#{region}/#{bucket}/#{object_key}/#{expires_in}")
          ) do
            url = presign_s3_url(
              region: region, bucket: bucket, object_key: object_key,
              expires_in: expires_in, access_key_id: access_key_id,
              secret_access_key: secret_access_key, session_token: session_token
            )
            {
              material: { "presigned_url" => url },
              ttl_seconds: lease_seconds(expires_at: expires_at, skew_seconds: skew)
            }
          end

          return base_credential if material.nil? || material["presigned_url"].to_s.empty?

          audit_log(data_source, "acquired", provider: "s3", expires_at: expires_at.utc.iso8601)
          BrokeredCredential.new(material, expires_at: expires_at)
        end

        # Build the Aws::S3::Presigner with EXPLICIT static credentials from the base
        # credential and presign a GET. Targets the FIXED regional AWS endpoint — no
        # config endpoint override is honored (security: fixed AWS endpoints only).
        def presign_s3_url(region:, bucket:, object_key:, expires_in:,
                           access_key_id:, secret_access_key:, session_token:)
          credentials =
            if session_token.to_s.empty?
              Aws::Credentials.new(access_key_id, secret_access_key)
            else
              Aws::Credentials.new(access_key_id, secret_access_key, session_token)
            end

          client = Aws::S3::Client.new(region: region, credentials: credentials)
          signer = Aws::S3::Presigner.new(client: client)
          signer.presigned_url(
            :get_object,
            bucket: bucket,
            key: object_key,
            expires_in: expires_in
          )
        end

        # Pull AWS keys off the BASE credential (never off config). Mirrors the
        # spelling order Sigv4Signer / VaultCredentialView use, plus the session
        # token via the credential's #[] pass-through.
        def aws_base_keys(base_credential)
          return [nil, nil, nil] if base_credential.nil?

          access_key_id =
            (base_credential.decrypted_api_key if base_credential.respond_to?(:decrypted_api_key))
          secret_access_key =
            (base_credential.decrypted_api_secret if base_credential.respond_to?(:decrypted_api_secret))
          session_token = bracket(base_credential, "session_token") || bracket(base_credential, "security_token")

          [access_key_id, secret_access_key, session_token]
        end

        # --------------------------------------------------------------------
        # (b) Azure Blob service SAS (HMAC-SHA256, no SDK)
        # --------------------------------------------------------------------

        def acquire_azure_sas(data_source:, base_credential:, config:)
          account_name = (cfg(config, :account_name) ||
            (base_credential.decrypted_api_key if base_credential.respond_to?(:decrypted_api_key))).to_s
          account_key_b64 =
            (base_credential.decrypted_api_secret if base_credential.respond_to?(:decrypted_api_secret)).to_s
          container = cfg(config, :container).to_s
          blob = cfg(config, :blob, :object_key, :key).to_s

          if account_name.empty? || account_key_b64.empty? || container.empty? || blob.empty?
            audit_log(data_source, "skipped", reason: "missing_azure_params")
            return base_credential
          end

          expires_in = clamp_expires(cfg(config, :expires_in), max: nil)
          skew = skew_seconds(config)
          # Anchor start slightly in the past to tolerate minor clock skew between us
          # and the storage service; expiry is start + lifetime.
          starts_at = Time.current - 60
          expires_at = Time.current + expires_in

          material = BrokerCache.fetch(
            cache_key_for(data_source, "azure_sas", account_name,
                          "#{container}/#{blob}/#{expires_in}")
          ) do
            url = build_azure_sas_url(
              account_name: account_name, account_key_b64: account_key_b64,
              container: container, blob: blob,
              starts_at: starts_at, expires_at: expires_at,
              endpoint_suffix: cfg(config, :endpoint_suffix).to_s
            )
            {
              material: { "presigned_url" => url },
              ttl_seconds: lease_seconds(expires_at: expires_at, skew_seconds: skew)
            }
          end

          return base_credential if material.nil? || material["presigned_url"].to_s.empty?

          audit_log(data_source, "acquired", provider: "azure_sas", expires_at: expires_at.utc.iso8601)
          BrokeredCredential.new(material, expires_at: expires_at)
        end

        # Construct the blob URL and append a freshly-computed service SAS.
        # DETERMINISTIC given the inputs (account/key/container/blob + the two
        # timestamps + version), so it is unit-testable with a frozen clock.
        def build_azure_sas_url(account_name:, account_key_b64:, container:, blob:,
                                starts_at:, expires_at:, endpoint_suffix:)
          suffix = endpoint_suffix.to_s.strip
          suffix = "core.windows.net" if suffix.empty?
          host = "#{account_name}.blob.#{suffix}"

          start_str = azure_time(starts_at)
          expiry_str = azure_time(expires_at)
          permissions = "r" # read-only presign

          # Canonicalized resource for a blob service SAS:
          #   /blob/<account>/<container>/<blob>
          canonical_resource = "/blob/#{account_name}/#{container}/#{blob}"

          # Service SAS string-to-sign field order for signed version 2020-12-06+.
          # Empty positions are REQUIRED (the newline-joined layout is positional);
          # omitting one shifts every later field and invalidates the signature.
          string_to_sign = [
            permissions,            # signedPermissions (sp)
            start_str,              # signedStart       (st)
            expiry_str,             # signedExpiry      (se)
            canonical_resource,     # canonicalizedResource
            "",                     # signedIdentifier  (si)
            "",                     # signedIP          (sip)
            "https",                # signedProtocol    (spr)
            AZURE_SAS_VERSION,      # signedVersion     (sv)
            AZURE_RESOURCE_BLOB,    # signedResource    (sr)
            "",                     # signedSnapshotTime
            "",                     # signedEncryptionScope
            "",                     # rscc  (Cache-Control)
            "",                     # rscd  (Content-Disposition)
            "",                     # rsce  (Content-Encoding)
            "",                     # rscl  (Content-Language)
            ""                      # rsct  (Content-Type)
          ].join("\n")

          signature = azure_sign(account_key_b64, string_to_sign)

          query = {
            "sv"  => AZURE_SAS_VERSION,
            "st"  => start_str,
            "se"  => expiry_str,
            "sr"  => AZURE_RESOURCE_BLOB,
            "sp"  => permissions,
            "spr" => "https",
            "sig" => signature
          }
          "https://#{host}/#{container}/#{blob}?#{azure_query_string(query)}"
        end

        # HMAC-SHA256 with the base64-DECODED account key, result base64-encoded.
        def azure_sign(account_key_b64, string_to_sign)
          key = Base64.decode64(account_key_b64)
          digest = OpenSSL::HMAC.digest(OpenSSL::Digest.new("SHA256"), key, string_to_sign)
          Base64.strict_encode64(digest)
        end

        # Azure SAS timestamps are ISO-8601 UTC to the second with a trailing Z.
        def azure_time(time)
          time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        end

        # Order-stable, percent-encoded SAS query string. Each value is encoded with
        # URI component escaping so the signature (which may contain +, /, =) and the
        # timestamps (which contain :) survive transport intact.
        def azure_query_string(params)
          params.map { |k, v| "#{k}=#{uri_escape(v)}" }.join("&")
        end

        def uri_escape(value)
          URI.encode_www_form_component(value.to_s)
        end

        # --------------------------------------------------------------------
        # shared helpers
        # --------------------------------------------------------------------

        # Read a field off a credential's #[] pass-through, tolerating either a
        # presence of the reader or a plain Hash; never raises.
        def bracket(credential, name)
          return nil unless credential.respond_to?(:[])

          credential[name]
        rescue StandardError
          nil
        end

        def clamp_expires(raw, max:)
          value = raw.to_i
          value = DEFAULT_EXPIRES_IN if value <= 0
          value = max if max && value > max
          value
        end

        def skew_seconds(config)
          cfg(config, :skew_seconds).to_i
        end

        # Build a STABLE, non-secret cache key. The base-credential principal is
        # folded in only as a SHA256 fingerprint (never the raw key) so two sources
        # with different creds don't share a cached URL, while the key itself leaks
        # nothing. Scope = broker + provider + source id + fingerprint + a resource
        # discriminator (region/bucket/object or container/blob + lifetime).
        def cache_key_for(data_source, provider, principal, resource)
          source_id = data_source.respond_to?(:id) ? data_source.id : "nil"
          fingerprint = Digest::SHA256.hexdigest("#{provider}:#{principal}")[0, 16]
          resource_digest = Digest::SHA256.hexdigest(resource.to_s)[0, 16]
          "presigned_url:#{provider}:#{source_id}:#{fingerprint}:#{resource_digest}"
        end
      end
    end
  end
end
