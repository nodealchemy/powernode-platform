# frozen_string_literal: true

module Ai
  module DataSources
    # Imports an OpenAPI 3 document into Ai::DataSourceEndpoint rows for a data
    # source. There is no openapi/json-schema gem available, so the spec is parsed
    # STRUCTURALLY: paths -> operations -> endpoints, with each operation's 200
    # response content schema resolved against components/schemas ($ref chasing)
    # and stored as the endpoint's response_schema.
    #
    # CONTRACT:
    #   Ai::DataSources::OpenApiImportService.new(data_source)
    #     #import(spec, dry_run: false) => {
    #       created: [<endpoint attrs/records>],   # persisted endpoints (or [] on dry_run)
    #       preview: [<endpoint attrs>],           # what would be / was created
    #       errors:  [<String>]
    #     }
    #
    # `spec` is an already-parsed OpenAPI 3 Hash. On dry_run the service returns the
    # preview without persisting anything.
    class OpenApiImportService
      # HTTP verbs recognized as operations under a path item.
      OPERATION_METHODS = %w[get post put patch delete head].freeze

      # Max ref-resolution depth — guards against cyclic $ref chains.
      MAX_REF_DEPTH = 25

      def initialize(data_source)
        @data_source = data_source
      end

      def import(spec, dry_run: false)
        errors = []
        spec = symbolize_top(spec)

        unless spec.is_a?(Hash) && spec["paths"].is_a?(Hash)
          return { created: [], preview: [], errors: ["spec missing 'paths' object"] }
        end

        previews = build_previews(spec, errors)

        return { created: [], preview: previews, errors: errors } if dry_run

        created = persist(previews, errors)
        { created: created, preview: previews, errors: errors }
      rescue StandardError => e
        Rails.logger.error("[OpenApiImportService] import failed: #{e.class}: #{e.message}")
        { created: [], preview: [], errors: ["import failed: #{e.message}"] }
      end

      private

      attr_reader :data_source

      # Build a preview attribute Hash for every (path, method) operation.
      def build_previews(spec, errors)
        previews = []
        spec["paths"].each do |path, path_item|
          next unless path_item.is_a?(Hash)

          OPERATION_METHODS.each do |method|
            operation = path_item[method] || path_item[method.to_sym]
            next unless operation.is_a?(Hash)

            previews << operation_attrs(path.to_s, method, operation)
          end
        rescue StandardError => e
          errors << "path #{path}: #{e.message}"
        end
        previews
      end

      # Map one OpenAPI operation to DataSourceEndpoint attributes.
      def operation_attrs(path, method, operation)
        name = operation_name(operation, method, path)
        {
          name: name,
          slug: slugify(operation["operationId"] || name),
          http_method: method.upcase,
          path_template: path,
          response_format: "json",
          response_schema: response_schema_for(operation),
          metadata: {
            "operation_id" => operation["operationId"],
            "summary" => operation["summary"],
            "tags" => operation["tags"],
            "imported_from" => "openapi",
            "source_path" => path,
            "source_method" => method.upcase
          }.compact
        }
      end

      # Endpoint name precedence: operationId -> summary -> "METHOD path".
      def operation_name(operation, method, path)
        operation["operationId"].presence ||
          operation["summary"].presence ||
          "#{method.upcase} #{path}"
      end

      # Resolve the 200 (then 2xx, then "default") response's JSON content schema,
      # chasing $ref against components/schemas. Returns {} when none is declared.
      def response_schema_for(operation)
        responses = operation["responses"]
        return {} unless responses.is_a?(Hash)

        response = responses["200"] || responses[200] ||
                   first_2xx(responses) || responses["default"]
        return {} unless response.is_a?(Hash)

        response = resolve_ref(response)
        content = response["content"]
        return {} unless content.is_a?(Hash)

        media = content["application/json"] || json_like_media(content)
        return {} unless media.is_a?(Hash)

        schema = media["schema"]
        schema.is_a?(Hash) ? resolve_schema(schema) : {}
      end

      def first_2xx(responses)
        key = responses.keys.find { |k| k.to_s.match?(/\A2\d\d\z/) }
        key ? responses[key] : nil
      end

      def json_like_media(content)
        key = content.keys.find { |k| k.to_s.include?("json") }
        key ? content[key] : nil
      end

      # Recursively resolve $ref nodes and inline referenced schemas so the stored
      # response_schema is self-contained (no dangling #/components/... pointers).
      def resolve_schema(schema, depth = 0)
        return {} if depth > MAX_REF_DEPTH
        return schema unless schema.is_a?(Hash)

        if schema.key?("$ref")
          return resolve_schema(dereference(schema["$ref"], depth), depth + 1)
        end

        schema.each_with_object({}) do |(key, value), acc|
          acc[key] =
            case value
            when Hash then resolve_schema(value, depth + 1)
            when Array then value.map { |v| v.is_a?(Hash) ? resolve_schema(v, depth + 1) : v }
            else value
            end
        end
      end

      # Resolve a single-level $ref wrapper (used for response objects).
      def resolve_ref(node, depth = 0)
        return node unless node.is_a?(Hash) && node.key?("$ref")
        return {} if depth > MAX_REF_DEPTH

        resolve_ref(dereference(node["$ref"], depth), depth + 1)
      end

      # Look up a local "#/components/schemas/Name" (or "#/components/responses/...")
      # pointer in the parsed spec. Returns {} for non-local or missing refs.
      def dereference(ref, _depth)
        return {} unless ref.is_a?(String) && ref.start_with?("#/")

        segments = ref.delete_prefix("#/").split("/")
        node = @full_spec
        segments.each do |seg|
          key = seg.gsub("~1", "/").gsub("~0", "~")
          node = node.is_a?(Hash) ? (node[key] || node[key.to_sym]) : nil
          break if node.nil?
        end
        node.is_a?(Hash) ? node : {}
      end

      # Persist previews as endpoints. Each is created independently; a failure on
      # one is recorded in errors and does not abort the rest. Duplicates are
      # SKIPPED by slug (per contract) rather than reported as errors — both
      # against slugs already present on the data source and slugs produced earlier
      # in this same batch (two operations can resolve to the same slug).
      def persist(previews, errors)
        created = []
        seen_slugs = existing_slugs
        previews.each do |attrs|
          slug = attrs[:slug]
          next if slug.present? && seen_slugs.include?(slug)

          endpoint = data_source.endpoints.build(attrs.except(:slug))
          endpoint.slug = slug if slug.present?
          if endpoint.save
            seen_slugs << endpoint.slug
            created << serialize(endpoint)
          else
            errors << "#{attrs[:name]}: #{endpoint.errors.full_messages.join(', ')}"
          end
        rescue StandardError => e
          errors << "#{attrs[:name]}: #{e.message}"
        end
        created
      end

      # Slugs already persisted under this data source, used to skip duplicates on
      # (re-)import. Falls back to an empty set for an unsaved/relation-less source.
      def existing_slugs
        data_source.endpoints.pluck(:slug).compact.to_set
      rescue StandardError
        Set.new
      end

      def serialize(endpoint)
        {
          id: endpoint.id,
          name: endpoint.name,
          slug: endpoint.slug,
          http_method: endpoint.http_method,
          path_template: endpoint.path_template,
          response_format: endpoint.response_format
        }
      end

      # Stringify top-level keys (so a symbol- or string-keyed parsed spec is
      # handled uniformly) and stash the full spec for $ref resolution.
      def symbolize_top(spec)
        normalized = spec.is_a?(Hash) ? spec.deep_stringify_keys : spec
        @full_spec = normalized
        normalized
      end

      def slugify(value)
        # underscore BEFORE parameterize: parameterize downcases first, which would
        # collapse camelCase word boundaries ("listStations" -> "liststations").
        # Underscoring first preserves them ("listStations" -> "list_stations").
        base = value.to_s.underscore.parameterize(separator: "_")
        base.presence || "endpoint_#{SecureRandom.hex(4)}"
      end
    end
  end
end
