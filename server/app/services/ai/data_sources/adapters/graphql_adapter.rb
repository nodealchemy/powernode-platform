# frozen_string_literal: true

require "json"

module Ai
  module DataSources
    module Adapters
      # GraphQL protocol adapter (protocol token "graphql").
      #
      # GraphQL is a single-endpoint, POST-only protocol: every operation is a POST
      # to the same URL carrying a JSON body of { query:, variables: }. This adapter
      # shapes that request from the stored endpoint templates and turns the
      # GraphQL JSON response (whose payload lives under the top-level "data" key)
      # into the canonical Array<Hash> the rest of the pipeline expects.
      #
      # Request shape
      # -------------
      # The GraphQL *document* (the `query`/mutation string) is sourced, in order:
      #
      #   1. params["query"] / params[:query]  — a caller-supplied operation, OR
      #   2. body_template["query"]            — the operation stored on the endpoint,
      #      OR (legacy convenience)
      #   3. query_template["query"]           — operation stored under query_template.
      #
      # Variables are sourced, in order:
      #
      #   1. params["variables"] (a Hash), merged over
      #   2. body_template["variables"] (interpolated like REST body values), merged
      #      over
      #   3. every *other* caller param (so `{ station_id: "X" }` becomes a GraphQL
      #      variable without the caller having to nest it under "variables").
      #
      # The reserved monitor hint key (MonitorService::CONDITIONAL_ETAG_PARAM,
      # "__conditional_etag") and the "query"/"variables" control keys are never
      # leaked into the variables map.
      #
      # The path is the endpoint's path_template (interpolated like REST so a
      # GraphQL gateway behind a sub-path still resolves); GraphQL servers ignore
      # query-string params, so none are emitted.
      #
      # Response shape
      # --------------
      # parse() decodes the JSON envelope and walks to the records:
      #
      #   * response_mapping["records_path"] (a.k.a. "root"/"data_path") when set —
      #     a dotted path / JSON pointer resolved against the WHOLE document, so an
      #     operator can target "data.stations" precisely; otherwise
      #   * the default GraphQL convention: descend into top-level "data", then, when
      #     "data" is a single-key object (the common `{ data: { field: ... } }`
      #     shape), unwrap that one field so the records are the field value.
      #
      # The located value is normalised to Array<Hash> with the same rules as the
      # JSON decoder (array -> each element; hash -> single record; scalar ->
      # { "value" => scalar }). GraphQL "errors" never raise here — a body with
      # errors and a null data still yields an empty record set (the QueryService
      # records the HTTP/anomaly outcome); we surface nothing secret.
      class GraphqlAdapter < Base
        # The single brace placeholder syntax shared with RestAdapter, reused for
        # interpolating the stored GraphQL document + variable templates.
        PLACEHOLDER = RestAdapter::PLACEHOLDER

        # Control keys in params that are NOT GraphQL variables.
        QUERY_KEY     = "query"
        VARIABLES_KEY = "variables"

        # The monitor's conditional-ETag hint param — never a GraphQL variable.
        # Referenced by string to avoid a hard load-order dependency on
        # MonitorService (which references adapters indirectly).
        CONDITIONAL_ETAG_PARAM = "__conditional_etag"

        # Builds the GraphQL POST request: same-URL POST, JSON { query:, variables: }.
        #
        # @param endpoint [Ai::DataSourceEndpoint]
        # @param params [Hash] caller params (operation/variables + variable values)
        # @return [Hash] { method:, url:, headers:, query:, body: }
        def build_request(endpoint:, params: {})
          values = stringify_params(params)

          {
            method: "POST",
            url: build_path(endpoint, values),
            headers: graphql_headers(endpoint),
            query: {},
            body: {
              "query" => graphql_document(endpoint, values),
              "variables" => graphql_variables(endpoint, values)
            }
          }
        end

        # Decode the GraphQL JSON envelope into canonical records. Honors an
        # explicit response_mapping records_path; otherwise unwraps "data".
        #
        # @param raw_body [String]
        # @param endpoint [Ai::DataSourceEndpoint]
        # @return [Array<Hash>]
        def parse(raw_body, endpoint:)
          text = Decoders::Registry::Charset.to_utf8(raw_body, charset: charset_for(endpoint))
          return [] if text.strip.empty?

          parsed = parse_json(text)
          return [] if parsed.nil?

          located = locate_records(parsed, endpoint)
          normalize_collection(located)
        end

        private

        # --- request helpers ----------------------------------------------------

        # Resolve the GraphQL operation string. A blank document is allowed through
        # (the server returns an error the QueryService records) rather than raising.
        def graphql_document(endpoint, values)
          explicit = values[QUERY_KEY]
          return explicit.to_s if explicit.present?

          stored = body_template_value(endpoint, QUERY_KEY) ||
                   query_template_value(endpoint, QUERY_KEY)
          return "" if stored.blank?

          interpolate(stored.to_s, values)
        end

        # Build the GraphQL variables map: template variables (interpolated) merged
        # under an explicit params["variables"] Hash, with every other non-control
        # caller param folded in as a top-level variable.
        def graphql_variables(endpoint, values)
          base = template_variables(endpoint, values)
          base = base.merge(loose_param_variables(values))
          base.merge(explicit_variables(values))
        end

        # Variables declared on the endpoint body_template under "variables".
        # Interpolated with the same whole-value/embedded rules as a REST body.
        def template_variables(endpoint, values)
          tmpl = body_template_value(endpoint, VARIABLES_KEY)
          return {} unless tmpl.is_a?(Hash)

          interpolate_hash(tmpl, values)
        end

        # An explicit params["variables"] Hash wins over loose/template variables.
        def explicit_variables(values)
          explicit = values[VARIABLES_KEY]
          explicit.is_a?(Hash) ? stringify_params(explicit) : {}
        end

        # Every caller param that is not a control key (query/variables) and not the
        # monitor's conditional hint becomes a top-level GraphQL variable. This lets
        # callers pass `{ id: 1 }` instead of `{ variables: { id: 1 } }`.
        def loose_param_variables(values)
          values.reject do |key, _value|
            key == QUERY_KEY || key == VARIABLES_KEY || key == CONDITIONAL_ETAG_PARAM
          end
        end

        # GraphQL is always JSON-in/JSON-out. Merge any static endpoint headers but
        # force the JSON content type (the dispatcher also defaults it, but being
        # explicit keeps the adapter self-describing).
        def graphql_headers(endpoint)
          headers = static_headers(endpoint)
          headers["Content-Type"] ||= "application/json"
          headers["Accept"] ||= "application/json"
          headers
        end

        def static_headers(endpoint)
          meta = endpoint&.metadata
          return {} unless meta.is_a?(Hash)

          raw = meta["headers"] || meta[:headers]
          return {} unless raw.is_a?(Hash)

          raw.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v.to_s }
        end

        # Interpolate the endpoint path (a GraphQL gateway may sit behind a path).
        def build_path(endpoint, values)
          template = endpoint&.path_template.to_s
          return "" if template.empty?

          interpolate(template, values, escape: :path)
        end

        # --- response helpers ---------------------------------------------------

        # Resolve the records node. Explicit records_path wins; otherwise apply the
        # GraphQL "data" unwrap convention.
        def locate_records(parsed, endpoint)
          path = records_path(endpoint)
          return resolve_path(parsed, path) if path.present?

          unwrap_data(parsed)
        end

        # Default GraphQL convention: take top-level "data"; if it is a single-key
        # object, unwrap that one field so the records are its value.
        def unwrap_data(parsed)
          return parsed unless parsed.is_a?(Hash)

          data = parsed.key?("data") ? parsed["data"] : parsed[:data]
          return data unless data.is_a?(Hash)
          return data unless data.size == 1

          data.values.first
        end

        # Resolve a dotted path / JSON pointer against the whole document (mirrors
        # the JSON decoder's segment walk so operators get identical semantics).
        def resolve_path(node, path)
          segments(path).reduce(node) do |current, key|
            break nil if current.nil?

            fetch_segment(current, key)
          end
        end

        def fetch_segment(current, key)
          case current
          when Hash
            current.key?(key) ? current[key] : current[key.to_s]
          when Array
            idx = Integer(key, exception: false)
            idx ? current[idx] : nil
          end
        end

        def segments(path)
          str = path.to_s
          if str.start_with?("/")
            str.split("/").reject(&:empty?)
          else
            str.split(".").reject(&:empty?)
          end
        end

        # Coerce an arbitrary located node into Array<Hash> (same contract as the
        # JSON decoder).
        def normalize_collection(node)
          case node
          when Array then node.map { |el| wrap_record(el) }
          when Hash  then [node]
          when nil   then []
          else [{ "value" => node }]
          end
        end

        def wrap_record(element)
          element.is_a?(Hash) ? element : { "value" => element }
        end

        def parse_json(text)
          JSON.parse(text)
        rescue JSON::ParserError => e
          Rails.logger.warn("[Adapters::GraphqlAdapter] parse failed: #{e.message}")
          nil
        end

        # --- shared interpolation (delegated to a private RestAdapter instance) --

        # Reuse RestAdapter's interpolation engine rather than duplicating it: a
        # whole-value "{var}" preserves type, an embedded "{var}" splices a String,
        # unknown placeholders are left intact. We borrow the private methods via a
        # memoized RestAdapter instance to keep one source of truth.
        def rest_interpolator
          @rest_interpolator ||= RestAdapter.new
        end

        def interpolate(str, values, escape: :none)
          rest_interpolator.send(:interpolate_string, str, values, escape: escape)
        end

        def interpolate_hash(hash, values)
          rest_interpolator.send(:interpolate_hash, hash, values, escape: :none)
        end

        # --- config helpers -----------------------------------------------------

        def body_template_value(endpoint, key)
          tmpl = endpoint&.body_template
          return nil unless tmpl.is_a?(Hash)

          tmpl[key] || tmpl[key.to_sym]
        end

        def query_template_value(endpoint, key)
          tmpl = endpoint&.query_template
          return nil unless tmpl.is_a?(Hash)

          tmpl[key] || tmpl[key.to_sym]
        end

        def records_path(endpoint)
          mapping = response_mapping(endpoint)
          mapping["records_path"] || mapping["root"] || mapping["data_path"] ||
            mapping[:records_path]
        end

        def response_mapping(endpoint)
          return {} unless endpoint.respond_to?(:response_mapping)

          mapping = endpoint.response_mapping
          mapping.is_a?(Hash) ? mapping : {}
        end

        def charset_for(endpoint)
          mapping = response_mapping(endpoint)
          mapping["charset"] || mapping[:charset]
        end
      end
    end
  end
end
