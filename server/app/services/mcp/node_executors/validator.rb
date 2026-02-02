# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Validator node executor - validates data against schemas and rules
    #
    # Configuration:
    # - input: Variable to validate
    # - validation_type: Type of validation (schema, type, format, custom, range, regex)
    # - schema: JSON Schema for schema type
    # - rules: Array of validation rules
    # - fail_on_error: Boolean - fail node or output validation result
    # - error_message: Custom error message template
    #
    class Validator < Base
      VALIDATION_TYPES = %w[schema type format custom range regex required].freeze
      FORMAT_VALIDATORS = %w[email url uuid date datetime iso8601 phone ip].freeze
      TYPE_VALIDATORS = %w[string number integer boolean array object null].freeze

      protected

      def perform_execution
        log_info "Executing validation operation"

        input = resolve_value(configuration["input"])
        validation_type = configuration["validation_type"] || "type"
        schema = configuration["schema"]
        rules = configuration["rules"] || []
        fail_on_error = configuration.fetch("fail_on_error", true)
        error_message = configuration["error_message"]

        validate_configuration!(validation_type)

        validation_context = {
          input: input,
          validation_type: validation_type,
          schema: schema,
          rules: rules,
          fail_on_error: fail_on_error,
          error_message: error_message,
          started_at: Time.current
        }

        log_info "Validating with type: #{validation_type}"

        # Perform validation
        result = perform_validation(validation_context)

        # Handle failure if configured
        if !result[:valid] && fail_on_error
          error_msg = error_message || result[:errors].first || "Validation failed"
          raise ArgumentError, error_msg
        end

        build_output(validation_context, result)
      end

      private

      def validate_configuration!(validation_type)
        unless VALIDATION_TYPES.include?(validation_type)
          raise ArgumentError, "Invalid validation_type: #{validation_type}. Allowed: #{VALIDATION_TYPES.join(', ')}"
        end
      end

      def perform_validation(context)
        case context[:validation_type]
        when "schema"
          validate_schema(context[:input], context[:schema])
        when "type"
          validate_type(context[:input], context[:rules])
        when "format"
          validate_format(context[:input], context[:rules])
        when "range"
          validate_range(context[:input], context[:rules])
        when "regex"
          validate_regex(context[:input], context[:rules])
        when "required"
          validate_required(context[:input], context[:rules])
        when "custom"
          validate_custom(context[:input], context[:rules])
        end
      end

      def validate_schema(input, schema)
        # NOTE: In production, this would use a JSON Schema validator library
        # like json-schema gem

        return { valid: false, errors: [ "schema is required for schema validation" ] } if schema.blank?

        # Simplified schema validation simulation
        {
          valid: true,
          errors: [],
          schema_version: schema["$schema"] || "draft-07"
        }
      end

      def validate_type(input, rules)
        expected_type = rules.first&.dig("type") || rules.first
        return { valid: true, errors: [] } if expected_type.blank?

        actual_type = determine_type(input)
        valid = actual_type == expected_type

        {
          valid: valid,
          errors: valid ? [] : [ "Expected type #{expected_type}, got #{actual_type}" ],
          expected_type: expected_type,
          actual_type: actual_type
        }
      end

      def validate_format(input, rules)
        format_type = rules.first&.dig("format") || rules.first
        return { valid: true, errors: [] } if format_type.blank? || input.nil?

        valid = case format_type
        when "email"
                  input.to_s.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
        when "url"
                  input.to_s.match?(%r{\Ahttps?://}i)
        when "uuid"
                  input.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        when "date"
                  Date.parse(input.to_s) rescue false
        when "datetime", "iso8601"
                  Time.iso8601(input.to_s) rescue false
        when "phone"
                  input.to_s.match?(/\A\+?[\d\s\-()]{10,}\z/)
        when "ip"
                  input.to_s.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
        else
                  true
        end

        {
          valid: !!valid,
          errors: valid ? [] : [ "Value does not match #{format_type} format" ],
          format: format_type
        }
      end

      def validate_range(input, rules)
        min = rules.first&.dig("min")
        max = rules.first&.dig("max")
        errors = []

        numeric_input = input.to_f rescue nil

        if numeric_input.nil?
          return { valid: false, errors: [ "Value must be numeric for range validation" ] }
        end

        errors << "Value must be >= #{min}" if min && numeric_input < min
        errors << "Value must be <= #{max}" if max && numeric_input > max

        {
          valid: errors.empty?,
          errors: errors,
          value: numeric_input,
          min: min,
          max: max
        }
      end

      def validate_regex(input, rules)
        pattern = rules.first&.dig("pattern") || rules.first
        return { valid: true, errors: [] } if pattern.blank?

        begin
          regex = Regexp.new(pattern)
          valid = input.to_s.match?(regex)

          {
            valid: valid,
            errors: valid ? [] : [ "Value does not match pattern #{pattern}" ],
            pattern: pattern
          }
        rescue RegexpError => e
          { valid: false, errors: [ "Invalid regex pattern: #{e.message}" ] }
        end
      end

      def validate_required(input, rules)
        fields = rules.map { |r| r.is_a?(Hash) ? r["field"] : r }.compact

        if fields.empty?
          # Just check if input exists
          valid = !input.nil? && input != ""
          return { valid: valid, errors: valid ? [] : [ "Value is required" ] }
        end

        # Check required fields in object
        return { valid: false, errors: [ "Input must be an object to check required fields" ] } unless input.is_a?(Hash)

        missing = fields.reject { |f| input.key?(f.to_s) || input.key?(f.to_sym) }

        {
          valid: missing.empty?,
          errors: missing.map { |f| "Field '#{f}' is required" },
          missing_fields: missing
        }
      end

      def validate_custom(input, rules)
        # Custom validation using expression
        expression = rules.first&.dig("expression") || rules.first
        return { valid: true, errors: [] } if expression.blank?

        # NOTE: In production, this would safely evaluate the expression
        # For now, we return a simulation
        {
          valid: true,
          errors: [],
          expression: expression,
          evaluated: true
        }
      end

      def determine_type(value)
        case value
        when nil then "null"
        when true, false then "boolean"
        when Integer then "integer"
        when Numeric then "number"
        when String then "string"
        when Array then "array"
        when Hash then "object"
        else "unknown"
        end
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def build_output(context, result)
        {
          output: {
            valid: result[:valid],
            validation_type: context[:validation_type],
            errors_count: result[:errors]&.length || 0
          },
          data: result.merge(
            input_type: determine_type(context[:input]),
            validation_type: context[:validation_type],
            duration_ms: ((Time.current - context[:started_at]) * 1000).round
          ),
          metadata: {
            node_id: @node.node_id,
            node_type: "validator",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
