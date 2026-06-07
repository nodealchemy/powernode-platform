# frozen_string_literal: true

require "erb"

module Ai
  module DataSources
    module Adapters
      # Generic REST/HTTP adapter.
      #
      # Handles the +rest+ and +custom+ protocols with ZERO per-source code: the
      # entire request shape is driven by the endpoint's stored templates and the
      # caller's params. This is the registry's generic fallback, so any data
      # source whose protocol is unrecognised also lands here and degrades safely.
      #
      # Template substitution
      # ---------------------
      # Three template surfaces are interpolated with caller params:
      #
      #   * +path_template+  (String) — e.g. "/v1/stations/{station_id}/obs"
      #   * +query_template+ (Hash)   — e.g. { "limit" => "{limit}", "fmt" => "json" }
      #   * +body_template+  (Hash)   — e.g. { "ids" => "{ids}", "fixed" => true }
      #
      # Placeholders use single-brace +{name}+ syntax. A placeholder is replaced
      # with +params[name]+ (string or symbol key). Two interpolation modes:
      #
      #   * Whole-value placeholder ("{limit}") in a Hash value — the value is
      #     replaced with the *raw* param (preserving Integer/Array/Boolean
      #     types) so structured bodies keep their JSON types.
      #   * Embedded placeholder ("/obs/{id}.json" or "prefix-{id}") — the param
      #     is stringified and spliced in; the result is always a String.
      #
      # Unknown placeholders (no matching param) are left intact rather than
      # blanked, so a misconfiguration surfaces visibly instead of silently
      # producing a malformed request. Path placeholders are URL-path-escaped;
      # query/body values are passed through untouched (the dispatcher encodes
      # them).
      #
      # Response parsing is inherited from Base (decoder-registry delegation).
      class RestAdapter < Base
        # Matches a single-brace placeholder: {name}, {snake_case}, {with-hyphen}.
        PLACEHOLDER = /\{([a-zA-Z0-9_.\-]+)\}/

        # Builds the outbound request hash from the endpoint templates + params.
        #
        # @param endpoint [Ai::DataSourceEndpoint]
        # @param params [Hash] caller-supplied parameters
        # @return [Hash] { method:, url:, headers:, query:, body: }
        def build_request(endpoint:, params: {})
          values = stringify_params(params)

          {
            method: normalized_method(endpoint),
            url: build_path(endpoint, values),
            headers: build_headers(endpoint),
            query: build_query(endpoint, values),
            body: build_body(endpoint, values)
          }
        end

        private

        # Interpolates the path template. Path placeholders are URL-path-escaped
        # so caller-supplied segments cannot break out of the path. Returns "" for
        # a blank template (the connection factory resolves against the base URL).
        def build_path(endpoint, values)
          template = endpoint&.path_template.to_s
          return "" if template.empty?

          interpolate_string(template, values, escape: :path)
        end

        # Interpolates the query template (a Hash). Values are interpolated; keys
        # are passed through as-is. Returns a String-keyed Hash. Nil-resulting
        # entries are dropped so optional params don't emit empty query keys.
        def build_query(endpoint, values)
          template = template_hash(endpoint&.query_template)
          return {} if template.empty?

          interpolate_hash(template, values, escape: :none).compact
        end

        # Interpolates the body template (a Hash). Returns the structured Hash
        # for the dispatcher to encode (JSON, form, etc.). Methods without a body
        # (GET/HEAD/DELETE) return nil so no body is sent.
        def build_body(endpoint, values)
          return nil unless body_allowed?(endpoint)

          template = template_hash(endpoint&.body_template)
          return nil if template.empty?

          interpolate_hash(template, values, escape: :none)
        end

        # Static headers stored on the endpoint metadata (auth/dynamic headers are
        # applied later by the signer layer, not here). Looks under
        # metadata["headers"] for an explicit Hash<String,String>.
        def build_headers(endpoint)
          meta = endpoint&.metadata
          return {} unless meta.is_a?(Hash)

          headers = meta["headers"] || meta[:headers]
          return {} unless headers.is_a?(Hash)

          headers.each_with_object({}) do |(key, value), memo|
            memo[key.to_s] = value.to_s
          end
        end

        # --- interpolation helpers ----------------------------------------------

        # Walks a Hash, interpolating every value (recursively for nested Hashes /
        # Arrays). Keys are left untouched.
        def interpolate_hash(hash, values, escape:)
          hash.each_with_object({}) do |(key, value), memo|
            memo[key.to_s] = interpolate_value(value, values, escape: escape)
          end
        end

        # Interpolates an arbitrary template value.
        #
        # A String that is *exactly* one placeholder ("{ids}") yields the raw
        # param (preserving type). Any other String is treated as a (possibly
        # embedded) template and produces a String. Hashes/Arrays recurse;
        # everything else is returned verbatim.
        def interpolate_value(value, values, escape:)
          case value
          when String
            interpolate_scalar_string(value, values, escape: escape)
          when Hash
            interpolate_hash(value, values, escape: escape)
          when Array
            value.map { |el| interpolate_value(el, values, escape: escape) }
          else
            value
          end
        end

        # Distinguishes a whole-value placeholder (return raw typed param) from an
        # embedded/literal template (return interpolated String).
        def interpolate_scalar_string(str, values, escape:)
          if (name = whole_placeholder(str))
            return values.key?(name) ? values[name] : str
          end

          interpolate_string(str, values, escape: escape)
        end

        # Returns the placeholder name when +str+ is exactly "{name}", else nil.
        def whole_placeholder(str)
          match = str.match(/\A#{PLACEHOLDER}\z/)
          match && match[1]
        end

        # Splices params into an embedded template, stringifying each substitution.
        # Unknown placeholders are preserved verbatim so misconfig is visible.
        def interpolate_string(str, values, escape:)
          str.gsub(PLACEHOLDER) do
            name = Regexp.last_match(1)
            if values.key?(name)
              escape_value(values[name].to_s, escape)
            else
              Regexp.last_match(0)
            end
          end
        end

        # Path segments are RFC 3986 escaped via the +erb+ stdlib (space => %20,
        # unreserved chars preserved, reserved chars including "/" escaped) so a
        # caller-supplied param cannot break out of its path segment. We avoid
        # CGI.escape here because it form-encodes spaces as "+", which is wrong
        # inside a URL path. Query/body values use :none — the dispatcher encodes
        # them when serialising the request.
        def escape_value(value, escape)
          case escape
          when :path then ERB::Util.url_encode(value)
          else value
          end
        end

        # --- misc ----------------------------------------------------------------

        # Coerces a stored template column into a Hash (guards against nil / a
        # legacy/empty value persisted as something other than a Hash).
        def template_hash(template)
          template.is_a?(Hash) ? template : {}
        end

        # GET/HEAD/DELETE conventionally carry no request body.
        def body_allowed?(endpoint)
          %w[POST PUT PATCH].include?(normalized_method(endpoint))
        end
      end
    end
  end
end
