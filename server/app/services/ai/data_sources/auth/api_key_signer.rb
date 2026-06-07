# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # Injects a static API key into the outbound request.
      #
      # The key value comes from the credential (#decrypted_api_key, or a plain
      # Hash's :api_key). Placement is driven by +config+ (the data source's
      # auth_config):
      #
      #   { "in" => "header", "name" => "X-API-Key" }   # default
      #   { "in" => "query",  "name" => "apikey" }
      #
      # An optional "prefix" prepends to the value (e.g. "Token " for
      # "Authorization: Token <key>" style schemes).
      class ApiKeySigner < BaseSigner
        DEFAULT_HEADER = "X-API-Key"
        DEFAULT_QUERY_PARAM = "api_key"

        def sign!(conn_or_env, credential:, config: {})
          key = api_key(credential)
          return if key.blank?

          cfg = (config || {}).with_indifferent_access
          value = "#{cfg[:prefix]}#{key}"

          case cfg[:in].to_s.downcase
          when "query"
            put_query(conn_or_env, cfg[:name].presence || DEFAULT_QUERY_PARAM, value)
          else
            put_header(conn_or_env, cfg[:name].presence || DEFAULT_HEADER, value)
          end
          nil
        end

        private

        def api_key(credential)
          return nil if credential.nil?

          if credential.respond_to?(:decrypted_api_key)
            credential.decrypted_api_key
          elsif credential.is_a?(Hash)
            credential.with_indifferent_access[:api_key]
          end
        end
      end
    end
  end
end
