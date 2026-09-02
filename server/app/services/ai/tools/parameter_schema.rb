# frozen_string_literal: true

module Ai
  module Tools
    # Converts a tool's parameter declaration into the JSON Schema an MCP client
    # is handed as `inputSchema`.
    #
    # WHY THIS IS ITS OWN SEAM (IMP-e809396f9eda): the MCP `inputSchema` surface
    # had two independent copies of this conversion —
    # McpPlatformToolRegistrar.convert_to_json_schema (the registry manifest and
    # the mcp_tools rows) and
    # Api::V1::Mcp::StreamableHttpController#build_input_schema (the tools/list
    # wire) — and BOTH copied exactly `type` and `description` per parameter.
    # Every other JSON Schema keyword a tool declared (`enum`, `items`,
    # `default`, nested `properties`) was dropped on the floor, so a closed value
    # set could only ever be stated in the description prose and an array
    # parameter reached the client untyped. Fixing one copy would have left the
    # other lying, which is exactly how the two drifted in the first place.
    #
    # SCOPE, so the count above is not overread as exhaustive: a THIRD converter
    # of the same declarations lives at Ai::AgentToolBridgeService
    # #convert_to_json_schema, for PROVIDER tool-calling (Anthropic/OpenAI
    # function schemas), not MCP. It is deliberately NOT unified here — it
    # already carried `enum` and these array/object defaults, and it answers to
    # provider schema dialects rather than to the MCP spec, so collapsing it
    # would couple two contracts that change for different reasons. It is the
    # precedent the defaults below copy.
    #
    # KEYWORDS ARE ALLOW-LISTED, not copied wholesale: a parameter declaration is
    # a tool-authoring DSL, not a schema. `required:` is that DSL's per-parameter
    # flag and is hoisted into the schema's `required` ARRAY (JSON Schema has no
    # per-property `required` boolean), and any other non-schema bookkeeping a
    # tool hangs off a parameter stays internal rather than leaking onto the wire.
    module ParameterSchema
      # JSON Schema keywords a tool parameter may declare, carried through
      # verbatim. `required` is deliberately absent — see the note above and
      # #property_for, which resolves the DSL-flag / nested-keyword collision.
      PASSTHROUGH_KEYWORDS = %w[
        enum items default properties additionalProperties
        format pattern const title
        minimum maximum exclusiveMinimum exclusiveMaximum multipleOf
        minLength maxLength minItems maxItems uniqueItems
        oneOf anyOf allOf not
        example examples nullable
      ].freeze

      # Strict clients (and several provider tool-calling APIs) reject an array
      # with no `items` and an object with no `properties`, so a declaration that
      # omits them gets the permissive default rather than an invalid schema.
      DEFAULT_ARRAY_ITEMS = { "type" => "string" }.freeze

      class << self
        # @param parameters [Hash, nil] either the flat authoring form
        #   ({ name => { type:, description:, required:, enum:, ... } }) or an
        #   already-complete JSON Schema object (root type == "object").
        # @return [Hash] string-keyed JSON Schema object
        def build(parameters)
          return deep_dup_empty if parameters.blank?

          return passthrough(parameters) if json_schema_object?(parameters)

          properties = {}
          required = []

          parameters.each do |param_name, param_def|
            next unless param_def.is_a?(Hash)

            properties[param_name.to_s] = property_for(param_def)
            # An ARRAY-valued `required` is JSON Schema's own keyword on a nested
            # object, not the DSL's per-parameter flag; #property_for carries it
            # through and it must not also mark the parameter itself required.
            flag = param_def.key?(:required) ? param_def[:required] : param_def["required"]
            required << param_name.to_s if flag && !flag.is_a?(Array)
          end

          { "type" => "object", "properties" => properties, "required" => required }
        end

        private

        def deep_dup_empty
          { "type" => "object", "properties" => {}, "required" => [] }
        end

        # A complete schema is recognised by its root type being the STRING
        # "object" — not merely by the presence of a `type` key. A tool may
        # legitimately declare a parameter NAMED `type` (Ai::Tools::
        # ActivityMonitorTool's notification filter does), and the key-presence
        # test the registrar used mistook that whole flat parameter hash for a
        # JSON Schema and shipped it verbatim as the action's inputSchema.
        def json_schema_object?(parameters)
          return false unless parameters.is_a?(Hash)

          root_type = parameters[:type] || parameters["type"]
          root_type.is_a?(String) || root_type.is_a?(Symbol) ? root_type.to_s == "object" : false
        end

        # An already-complete schema is the tool's own word on the contract —
        # carry it verbatim, normalising key/`required` types for JSON and
        # filling the two containers the wire shape has always carried.
        def passthrough(parameters)
          schema = parameters.deep_stringify_keys
          props = schema["properties"]
          if props.is_a?(Hash)
            schema["properties"] = props.each_with_object({}) do |(name, spec), acc|
              acc[name.to_s] = spec.is_a?(Hash) ? spec : { "type" => spec.to_s }
            end
          end
          # `required` and `properties` are emitted even when the tool omits
          # them: that is the shape the streamable-HTTP controller has always put
          # on the wire (four tools declare `{ type: "object", properties: {} }`
          # and got `"required": []`), and unifying the two copies must not
          # quietly change it.
          schema["properties"] ||= {}
          schema["required"] = Array(schema["required"]).map(&:to_s)
          schema
        end

        def property_for(param_def)
          type = (param_def[:type] || param_def["type"] || "string").to_s
          prop = { "type" => type }

          description = param_def[:description] || param_def["description"]
          prop["description"] = description if description.present?

          PASSTHROUGH_KEYWORDS.each do |keyword|
            next unless param_def.key?(keyword.to_sym) || param_def.key?(keyword)

            value = param_def.key?(keyword.to_sym) ? param_def[keyword.to_sym] : param_def[keyword]
            next if value.nil?

            prop[keyword] = value.is_a?(Hash) ? value.deep_stringify_keys : value
          end

          # See #build: an Array here is the nested-object keyword, and it is the
          # only reading under which a `required` on a parameter reaches the wire.
          nested_required = param_def.key?(:required) ? param_def[:required] : param_def["required"]
          prop["required"] = nested_required.map(&:to_s) if nested_required.is_a?(Array)

          prop["items"] ||= DEFAULT_ARRAY_ITEMS.dup if type == "array"
          prop["additionalProperties"] = true if type == "object" && !prop.key?("properties") && !prop.key?("additionalProperties")

          prop
        end
      end
    end
  end
end
