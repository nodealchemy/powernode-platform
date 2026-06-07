# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # Injects an RFC 6750 bearer token: "Authorization: Bearer <token>".
      #
      # The token comes from the credential (#decrypted_api_key, or a plain
      # Hash's :api_key / :token). +config+ may override the header name and the
      # scheme word for non-standard deployments:
      #
      #   { "header" => "Authorization", "scheme" => "Bearer" }   # defaults
      class BearerSigner < BaseSigner
        DEFAULT_HEADER = "Authorization"
        DEFAULT_SCHEME = "Bearer"

        def sign!(conn_or_env, credential:, config: {})
          token = bearer_token(credential)
          return if token.blank?

          cfg = (config || {}).with_indifferent_access
          header = cfg[:header].presence || DEFAULT_HEADER
          scheme = cfg.key?(:scheme) ? cfg[:scheme].to_s : DEFAULT_SCHEME
          value = scheme.present? ? "#{scheme} #{token}" : token

          put_header(conn_or_env, header, value)
          nil
        end

        private

        def bearer_token(credential)
          return nil if credential.nil?

          if credential.respond_to?(:decrypted_api_key)
            credential.decrypted_api_key
          elsif credential.is_a?(Hash)
            hash = credential.with_indifferent_access
            hash[:token] || hash[:api_key]
          end
        end
      end
    end
  end
end
