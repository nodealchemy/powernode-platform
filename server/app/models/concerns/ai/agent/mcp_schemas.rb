# frozen_string_literal: true

module Ai
  class Agent
    module McpSchemas
      extend ActiveSupport::Concern

      included do
        before_validation :set_default_mcp_schemas

        validate :mcp_tool_manifest_valid
        validate :mcp_input_schema_valid
        validate :mcp_output_schema_valid
      end

      # Validate input against MCP schema
      def validate_mcp_input(input_data)
        return true if mcp_input_schema.blank?

        begin
          validator = JsonSchemaValidator.new(mcp_input_schema)
          validator.valid?(input_data)
        rescue StandardError => e
          Rails.logger.warn "[AGENT_MCP] Input validation error: #{e.message}"
          false
        end
      end

      # Validate output against MCP schema
      def validate_mcp_output(output_data)
        return true if mcp_output_schema.blank?

        begin
          validator = JsonSchemaValidator.new(mcp_output_schema)
          validator.valid?(output_data)
        rescue StandardError => e
          Rails.logger.warn "[AGENT_MCP] Output validation error: #{e.message}"
          false
        end
      end

      # Default input schema for MCP protocol
      def default_input_schema
        self.class.default_input_schema
      end

      # Default output schema for MCP protocol
      def default_output_schema
        self.class.default_output_schema
      end

      class_methods do
        def default_input_schema
          {
            "type" => "object",
            "properties" => {
              "input" => {
                "type" => "string",
                "description" => "Primary input text for the AI agent",
                "minLength" => 1,
                "maxLength" => 100000
              },
              "context" => {
                "type" => "object",
                "description" => "Additional context for the agent execution",
                "properties" => {
                  "temperature" => {
                    "type" => "number",
                    "minimum" => 0,
                    "maximum" => 2,
                    "description" => "Sampling temperature for response generation"
                  },
                  "max_tokens" => {
                    "type" => "integer",
                    "minimum" => 1,
                    "maximum" => 32000,
                    "description" => "Maximum number of tokens to generate"
                  }
                },
                "additionalProperties" => true
              }
            },
            "required" => [ "input" ],
            "additionalProperties" => false
          }
        end

        def default_output_schema
          {
            "type" => "object",
            "properties" => {
              "output" => {
                "type" => "string",
                "description" => "Generated response from the AI agent"
              },
              "metadata" => {
                "type" => "object",
                "description" => "Additional metadata about the response",
                "properties" => {
                  "tokens_used" => {
                    "type" => "integer",
                    "description" => "Number of tokens consumed"
                  },
                  "processing_time_ms" => {
                    "type" => "number",
                    "description" => "Processing time in milliseconds"
                  },
                  "model_used" => {
                    "type" => "string",
                    "description" => "AI model used for generation"
                  }
                },
                "additionalProperties" => true
              },
              "error" => {
                "type" => "string",
                "description" => "Error message if execution failed"
              }
            },
            "required" => [ "output" ],
            "additionalProperties" => false
          }
        end
      end

      private

      def set_default_mcp_schemas
        self.mcp_input_schema = default_input_schema if mcp_input_schema.blank?
        self.mcp_output_schema = default_output_schema if mcp_output_schema.blank?
      end

      def mcp_tool_manifest_valid
        return if mcp_tool_manifest.blank?

        unless mcp_tool_manifest.is_a?(Hash)
          errors.add(:mcp_tool_manifest, "must be a valid JSON object")
          return
        end

        # Validate required fields for tool manifests
        required_fields = %w[name description type version]
        missing_fields = required_fields - mcp_tool_manifest.keys

        if missing_fields.any?
          errors.add(:mcp_tool_manifest, "missing required fields: #{missing_fields.join(', ')}")
        end
      end

      def mcp_input_schema_valid
        validate_json_schema(mcp_input_schema, :mcp_input_schema)
      end

      def mcp_output_schema_valid
        validate_json_schema(mcp_output_schema, :mcp_output_schema)
      end

      def validate_json_schema(schema, field_name)
        return if schema.blank?

        unless schema.is_a?(Hash)
          errors.add(field_name, "must be a valid JSON schema object")
          return
        end

        # Basic JSON Schema validation
        unless schema["type"].present?
          errors.add(field_name, "must include a type field")
        end
      end
    end
  end
end
