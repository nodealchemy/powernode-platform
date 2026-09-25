# frozen_string_literal: true

module Ai
  module Llm
    # Brings a caller's JSON Schema into the strict form structured output
    # accepts, once, in every adapter's structured path. DUPLICATED verbatim in the
    # server and the worker (no shared lib across the apps, like
    # ModelCapabilities). Keep the two copies in sync.
    #
    # Anthropic output_config.format requires additionalProperties: false on every
    # object and rejects numeric, length and some array constraints; OpenAI strict
    # json_schema additionally requires every property to be listed in
    # `required`. A schema written without these rules either 400s or, where a
    # caller swallows the error, reads as an empty response. So:
    #   - an object that does not say additionalProperties is closed (false);
    #   - every property becomes required, and one that was optional becomes
    #     nullable (null added to its type, or anyOf with null), so "absent"
    #     arrives as null;
    #   - keywords the provider does not support are dropped (the bound belongs in
    #     the prompt or in code).
    # An object that is meant to be open (additionalProperties true or a schema,
    # or an object with no properties at all) cannot be expressed strictly.
    # Closing it would silently change what the caller asked for, so it RAISES.
    # Reshape such a field (e.g. a map into [{name, value}]) instead.
    module StructuredSchema
      class OpenMapError < ArgumentError; end

      BOUNDS = %w[minimum maximum exclusiveMinimum exclusiveMaximum multipleOf
                  minLength maxLength pattern minItems maxItems uniqueItems
                  minProperties maxProperties patternProperties].freeze
      UNSUPPORTED = { anthropic: BOUNDS, openai: BOUNDS, ollama: [].freeze }.freeze
      COMPOSITES = %w[anyOf allOf oneOf].freeze

      module_function

      # @param schema [Hash] a JSON Schema (symbol or string keys)
      # @param provider [Symbol] :anthropic, :openai or :ollama
      # @return [Hash] the strict schema, string keys
      def normalize(schema, provider:)
        drop = UNSUPPORTED.fetch(provider.to_sym)
        walk(stringify(schema), drop, "$")
      end

      def walk(node, drop, path)
        return node unless node.is_a?(Hash)

        node = node.except(*drop)
        node = close_object(node, drop, path) if object?(node)
        node["items"] = walk(node["items"], drop, "#{path}.items") if node["items"].is_a?(Hash)
        COMPOSITES.each do |key|
          next unless node[key].is_a?(Array)

          node[key] = node[key].each_with_index.map { |sub, i| walk(sub, drop, "#{path}.#{key}[#{i}]") }
        end
        %w[$defs definitions].each do |key|
          next unless node[key].is_a?(Hash)

          node[key] = node[key].to_h { |name, sub| [ name, walk(sub, drop, "#{path}.#{key}.#{name}") ] }
        end
        node
      end

      def close_object(node, drop, path)
        open = node["additionalProperties"]
        if open == true || open.is_a?(Hash)
          raise OpenMapError, "#{path}: an open object (additionalProperties #{open.inspect}) cannot be " \
                              "expressed in strict structured output; reshape it (e.g. into [{name, value}])"
        end
        properties = node["properties"]
        if !properties.is_a?(Hash) || properties.empty?
          raise OpenMapError, "#{path}: an object with no properties cannot be expressed in strict structured " \
                              "output; declare its properties or reshape it"
        end

        required = Array(node["required"]).map(&:to_s)
        node.merge(
          "additionalProperties" => false,
          "required" => properties.keys,
          "properties" => properties.to_h do |name, sub|
            sub = walk(sub, drop, "#{path}.#{name}")
            [ name, required.include?(name) ? sub : nullable(sub) ]
          end
        )
      end

      def nullable(node)
        return node unless node.is_a?(Hash)

        type = node["type"]
        if type.is_a?(String)
          return node if type == "null"

          with_null_enum(node.merge("type" => [ type, "null" ]))
        elsif type.is_a?(Array)
          type.include?("null") ? node : with_null_enum(node.merge("type" => type + [ "null" ]))
        else
          { "anyOf" => [ node, { "type" => "null" } ] }
        end
      end

      # A nullable enum must list null among its values, or null never validates.
      def with_null_enum(node)
        return node unless node["enum"].is_a?(Array) && !node["enum"].include?(nil)

        node.merge("enum" => node["enum"] + [ nil ])
      end

      def object?(node)
        type = node["type"]
        type == "object" || (type.is_a?(Array) && type.include?("object")) ||
          (type.nil? && node.key?("properties"))
      end

      def stringify(value)
        case value
        when Hash then value.to_h { |k, v| [ k.to_s, stringify(v) ] }
        when Array then value.map { |v| stringify(v) }
        else value
        end
      end
    end
  end
end
