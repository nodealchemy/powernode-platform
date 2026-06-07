# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # RFC 9421 (HTTP Message Signatures) HMAC signer.
      #
      # Builds a signature base from a configurable set of covered components,
      # signs it with Security::HttpSignature (the shared HMAC/secure-compare
      # module also used by inbound webhook verification), and emits the
      # `Signature-Input` and `Signature` headers per RFC 9421.
      #
      # The shared secret comes from the credential (#decrypted_api_secret, or a
      # plain Hash's :secret / :hmac_secret). A non-secret key id (#decrypted_api_key
      # or :key_id) is advertised via the signature parameters' `keyid`.
      #
      # +config+ (the data source's auth_config) knobs:
      #   {
      #     "components" => ["@method", "@target-uri", "date"], # covered fields
      #     "algorithm"  => "sha256",          # HMAC digest (=> "hmac-sha256" label)
      #     "label"      => "sig1",            # signature label
      #     "key_id"     => "primary"          # optional keyid override
      #   }
      #
      # Default covered components are @method and @target-uri plus a generated
      # `date` header, which the signer also injects so the receiver can verify.
      class HmacSigner < BaseSigner
        DEFAULT_COMPONENTS = %w[@method @target-uri].freeze
        DEFAULT_ALGORITHM = "sha256"
        DEFAULT_LABEL = "sig1"

        def sign!(conn_or_env, credential:, config: {})
          secret = hmac_secret(credential)
          if secret.blank?
            Rails.logger.warn("[HmacSigner] missing HMAC secret; request left unsigned")
            return
          end

          cfg = (config || {}).with_indifferent_access
          algorithm = cfg[:algorithm].presence || DEFAULT_ALGORITHM
          label = cfg[:label].presence || DEFAULT_LABEL
          components = Array(cfg[:components].presence || DEFAULT_COMPONENTS).map(&:to_s)

          # Ensure a `date` header exists when it is a covered component so the
          # value we sign matches what the peer receives.
          ensure_date_header(conn_or_env) if components.include?("date")

          created = Time.current.to_i
          params = signature_params(components, created, algorithm, key_id(credential, cfg))

          base = signature_base(conn_or_env, components, label, params)
          mac = ::Security::HttpSignature.base64digest(secret: secret, data: base, algorithm: algorithm)

          put_header(conn_or_env, "Signature-Input", "#{label}=#{params}")
          put_header(conn_or_env, "Signature", "#{label}=:#{mac}:")
          nil
        end

        private

        # Builds the RFC 9421 signature base: one line per covered component in
        # declared order, then the "@signature-params" line.
        def signature_base(target, components, _label, params)
          headers = read_headers(target).transform_keys { |k| k.to_s.downcase }
          method = read_method(target)
          uri = read_url(target)

          lines = components.map do |component|
            value =
              case component
              when "@method"     then method
              when "@target-uri" then uri
              else headers[component.downcase].to_s
              end
            %("#{component}": #{value})
          end
          lines << %("@signature-params": #{params})
          lines.join("\n")
        end

        # Serializes the signature parameters component value, e.g.
        #   ("@method" "@target-uri");created=123;alg="hmac-sha256";keyid="primary"
        def signature_params(components, created, algorithm, key_id)
          covered = components.map { |c| %("#{c}") }.join(" ")
          parts = ["(#{covered})", "created=#{created}", %(alg="hmac-#{algorithm.to_s.downcase}")]
          parts << %(keyid="#{key_id}") if key_id.present?
          parts.join(";")
        end

        def ensure_date_header(target)
          existing = read_headers(target).find { |k, _| k.to_s.casecmp("date").zero? }
          return if existing && existing.last.present?

          put_header(target, "Date", Time.current.httpdate)
        end

        def hmac_secret(credential)
          return nil if credential.nil?

          if credential.respond_to?(:decrypted_api_secret)
            credential.decrypted_api_secret
          elsif credential.is_a?(Hash)
            hash = credential.with_indifferent_access
            hash[:secret] || hash[:hmac_secret]
          end
        end

        def key_id(credential, cfg)
          return cfg[:key_id] if cfg[:key_id].present?
          return nil if credential.nil?

          if credential.respond_to?(:decrypted_api_key)
            credential.decrypted_api_key
          elsif credential.is_a?(Hash)
            credential.with_indifferent_access[:key_id]
          end
        end
      end
    end
  end
end
