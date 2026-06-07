# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # AWS Signature Version 4 signer.
      #
      # WRAPS Aws::Sigv4::Signer (gem aws-sigv4, bundled via aws-sdk-s3) — the
      # canonical-request / string-to-sign / signing-key derivation is delegated
      # entirely to the SDK. We never hand-roll canonicalization.
      #
      # Region and service come from +config+ (the data source's auth_config):
      #   { "region" => "us-east-1", "service" => "execute-api",
      #     "session_token" => "..."(optional) }
      #
      # access_key_id / secret_access_key come from the credential
      # (#decrypted_api_key => access key id, #decrypted_api_secret => secret),
      # or from a plain Hash. The optional session token may live on either the
      # credential or config.
      #
      # SigV4 must canonicalize the method + URL + body together, so this signer
      # only supports the request-env Hash target (the Adapter's output). Signing
      # a bare Faraday::Connection (no path/body) is unsupported and skipped — a
      # SigV4 request must be signed per-request, not per-connection.
      class Sigv4Signer < BaseSigner
        DEFAULT_SERVICE = "execute-api"

        def sign!(conn_or_env, credential:, config: {})
          if faraday_connection?(conn_or_env)
            Rails.logger.warn(
              "[Sigv4Signer] cannot sign a bare Faraday::Connection; " \
              "SigV4 requires per-request method/url/body — skipping"
            )
            return
          end

          cfg = (config || {}).with_indifferent_access
          access_key_id, secret_access_key, session_token = aws_keys(credential, cfg)

          if access_key_id.blank? || secret_access_key.blank?
            Rails.logger.warn("[Sigv4Signer] missing AWS credentials; request left unsigned")
            return
          end

          region = cfg[:region].presence
          if region.blank?
            Rails.logger.warn("[Sigv4Signer] missing AWS region in auth_config; request left unsigned")
            return
          end

          signer = Aws::Sigv4::Signer.new(
            service: cfg[:service].presence || DEFAULT_SERVICE,
            region: region,
            access_key_id: access_key_id,
            secret_access_key: secret_access_key,
            session_token: session_token
          )

          signature = signer.sign_request(
            http_method: read_method(conn_or_env),
            url: read_url(conn_or_env),
            headers: read_headers(conn_or_env),
            body: read_body(conn_or_env) || ""
          )

          # sign_request returns the headers (host, x-amz-date,
          # x-amz-content-sha256, authorization, x-amz-security-token) that must
          # be applied verbatim to the outbound request.
          signature.headers.each do |name, value|
            put_header(conn_or_env, name, value)
          end
          nil
        end

        private

        # @return [Array(String, String, String)] [access_key_id, secret, session_token]
        def aws_keys(credential, cfg)
          hash = credential.is_a?(Hash) ? credential.with_indifferent_access : nil

          access_key_id =
            if credential.respond_to?(:decrypted_api_key)
              credential.decrypted_api_key
            elsif hash
              hash[:access_key_id]
            end

          secret_access_key =
            if credential.respond_to?(:decrypted_api_secret)
              credential.decrypted_api_secret
            elsif hash
              hash[:secret_access_key]
            end

          session_token = hash && hash[:session_token]
          session_token ||= cfg[:session_token].presence

          [access_key_id, secret_access_key, session_token]
        end
      end
    end
  end
end
