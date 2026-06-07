# frozen_string_literal: true

module Ai
  module DataSources
    module Adapters
      # Base class for request/response adapters.
      #
      # An adapter is the protocol-aware translation layer between a stored
      # +Ai::DataSourceEndpoint+ definition (+path_template+, +query_template+,
      # +body_template+, +response_format+, ...) and the concrete bytes that go
      # out on the wire / come back from the source. It is deliberately ignorant
      # of *how* the request is dispatched (that is the HttpConnectionFactory /
      # QueryService's job) and of *how* records are normalised afterwards (that
      # is NormalizationService's job). It only knows how to:
      #
      #   1. shape the outbound request from a template + caller params, and
      #   2. turn a raw response body into canonical Array<Hash> records.
      #
      # CONTRACT (every adapter conforms so the layers compose):
      #
      #   adapter.build_request(endpoint:, params:)
      #     => { method:, url:, headers:, query:, body: }
      #        - +method+  : upper-case HTTP verb String (e.g. "GET")
      #        - +url+     : path/URL String after template substitution (may be
      #                      relative to the data source base URL; the connection
      #                      factory resolves it against the configured base)
      #        - +headers+ : Hash<String,String> of request headers
      #        - +query+   : Hash of query-string params (String keys/values)
      #        - +body+    : request body — Hash for structured bodies (the
      #                      dispatcher encodes it), String for raw bodies, or nil
      #
      #   adapter.parse(raw_body, endpoint:)
      #     => Array<Hash> (canonical records)
      #        Delegates format selection + decoding to
      #        Ai::DataSources::Decoders::Registry. Never raises on a malformed
      #        body — a body that cannot be decoded yields an empty record set
      #        (the decoder logs; the QueryService records the anomaly).
      #
      # Subclasses MUST implement +build_request+. +parse+ has a protocol-agnostic
      # default here (decoder delegation) that is correct for every HTTP/REST-ish
      # source, so most adapters only need to override +build_request+.
      class Base
        # @param endpoint [Ai::DataSourceEndpoint]
        # @param params [Hash] caller-supplied parameters for interpolation
        # @return [Hash] { method:, url:, headers:, query:, body: }
        def build_request(endpoint:, params: {})
          raise NotImplementedError, "#{self.class}#build_request must be implemented"
        end

        # Decodes a raw response body into canonical records by delegating to the
        # decoder registry. Shared by all adapters; override only when a protocol
        # needs bespoke pre-processing before decoding.
        #
        # @param raw_body [String]
        # @param endpoint [Ai::DataSourceEndpoint]
        # @return [Array<Hash>] canonical records (never nil)
        def parse(raw_body, endpoint:)
          decoder = Decoders::Registry.for(
            format: endpoint&.response_format,
            content_type: endpoint&.expected_content_type
          )
          records = decoder.decode(raw_body, endpoint: endpoint)
          records.is_a?(Array) ? records : []
        end

        protected

        # Normalises an HTTP method into the upper-case verb the contract expects,
        # defaulting to GET when blank/unknown. Endpoint-level validation already
        # restricts the column to HTTP_METHODS, so this is a defensive fallback.
        def normalized_method(endpoint)
          method = endpoint&.http_method.to_s.strip.upcase
          method.empty? ? "GET" : method
        end

        # Returns the params Hash with indifferent-ish access: a frozen-safe dup
        # whose keys are stringified, so callers may pass symbol or string keys
        # interchangeably into templates.
        def stringify_params(params)
          return {} if params.blank?

          params.each_with_object({}) do |(key, value), memo|
            memo[key.to_s] = value
          end
        end
      end
    end
  end
end
