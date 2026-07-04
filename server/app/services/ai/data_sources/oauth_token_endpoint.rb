# frozen_string_literal: true

require "base64"
require "json"

module Ai
  module DataSources
    # Shared HTTP-response mechanics for an OAuth2 token-endpoint POST
    # (authorization_code exchange, refresh_token grant, or client_credentials
    # grant): the HTTP Basic client-auth header and tolerant JSON parsing of the
    # endpoint's response. Extracted from OauthAuthorizationCodeService (I1) so
    # Oauth2AuthorizationCodeBroker (I3's silent refresh) does not re-implement
    # the same response parsing.
    #
    # Callers still own: the SSRF-guarded connection (HttpConnectionFactory.build
    # / BaseBroker#broker_http_connection), the form fields for their specific
    # grant_type, and their own error-handling convention — I1 rescues transport
    # errors locally and returns a nil-tuple sentinel; Oauth2AuthorizationCodeBroker
    # lets them propagate to BaseBroker#acquire's degrade-and-log rescue. This
    # module does NOT rescue anything, so it never hides a transport error from
    # either caller's chosen strategy.
    #
    # SECURITY: never logs the response body, tokens, or client_secret.
    module OauthTokenEndpoint
      module_function

      def basic_auth_header(client_id, client_secret)
        "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}"
      end

      # Parse a token endpoint's response into a tolerant Hash with string keys
      # "access_token", "refresh_token", "expires_in" (Integer, clamped to
      # max_ttl_seconds, or nil), "scope". A non-2xx, non-JSON, or token-less
      # body returns an EMPTY Hash (never raises) so callers can uniformly check
      # `result["access_token"].blank?`. NEVER surfaces raw response content —
      # only the extracted fields are returned.
      #
      # @param response [#status, #body] a Faraday::Response (or double).
      # @param max_ttl_seconds [Integer, nil] clamp for an absurd expires_in.
      def parse_response(response, max_ttl_seconds: nil)
        return {} unless response.respond_to?(:status)
        return {} unless (200..299).cover?(response.status)

        body = response.body
        parsed = body.is_a?(Hash) ? body : parse_json(body)
        return {} unless parsed.is_a?(Hash)

        expires_in = (parsed["expires_in"] || parsed[:expires_in]).to_i
        expires_in = max_ttl_seconds if max_ttl_seconds && expires_in > max_ttl_seconds

        {
          "access_token" => (parsed["access_token"] || parsed[:access_token]).presence,
          "refresh_token" => (parsed["refresh_token"] || parsed[:refresh_token]).presence,
          "expires_in" => (expires_in.positive? ? expires_in : nil),
          "scope" => parsed["scope"] || parsed[:scope]
        }
      end

      # Normalize a token response's `scope` field (space/comma-delimited String,
      # Array, or blank) into an Array<String>.
      def normalize_scopes(scope)
        return [] if scope.blank?
        return scope.map(&:to_s) if scope.is_a?(Array)

        scope.to_s.split(/[\s,]+/).reject(&:blank?)
      end

      def parse_json(body)
        str = body.to_s
        return nil if str.empty?

        JSON.parse(str)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
