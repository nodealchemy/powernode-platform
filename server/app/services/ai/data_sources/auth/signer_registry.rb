# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # Resolves an outbound request signer for a data source's auth scheme.
      #
      # CONTRACT (every signer conforms):
      #   signer.sign!(conn_or_env, credential:, config:)
      #     - mutates the outbound request in place
      #     - +conn_or_env+ is either a Faraday::Connection or a plain mutable
      #       request-env Hash ({ method:, url:, headers:, query:, body: })
      #     - +credential+ is an Ai::DataSourceCredential (or any object
      #       responding to #decrypted_api_key / #decrypted_api_secret), or nil
      #     - +config+ is the data source's auth_config Hash (scheme-specific
      #       knobs: header/param names, region, service, algorithm, etc.)
      #
      # Generic 'none' fallback: unknown or blank schemes resolve to NoneSigner,
      # which performs no mutation. This mirrors the generic-fallback registry
      # shape used elsewhere (e.g. Ai::Providers::Sync::Generic) so adding a new
      # source with an unrecognized scheme degrades safely instead of raising.
      module SignerRegistry
        module_function

        # Canonical scheme => signer class map. Schemes are matched
        # case-insensitively after normalization.
        SIGNERS = {
          "none"       => "Ai::DataSources::Auth::NoneSigner",
          "api_key"    => "Ai::DataSources::Auth::ApiKeySigner",
          "bearer"     => "Ai::DataSources::Auth::BearerSigner",
          "aws_sigv4"  => "Ai::DataSources::Auth::Sigv4Signer",
          "hmac"       => "Ai::DataSources::Auth::HmacSigner"
        }.freeze

        # @param auth_scheme [String, Symbol, nil]
        # @return [#sign!] a signer instance conforming to the CONTRACT
        def for(auth_scheme)
          class_name = SIGNERS.fetch(normalize(auth_scheme), SIGNERS["none"])
          class_name.constantize.new
        end

        # @return [Array<String>] the registered scheme names
        def schemes
          SIGNERS.keys
        end

        def normalize(auth_scheme)
          key = auth_scheme.to_s.strip.downcase
          key.empty? ? "none" : key
        end
        private_class_method :normalize
      end
    end
  end
end
