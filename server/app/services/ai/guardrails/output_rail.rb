# frozen_string_literal: true

module Ai
  module Guardrails
    class OutputRail
      BUILT_IN_RAILS = %w[
        token_limit
        toxicity
        pii_detection
        hallucination_check
        format_validation
        structured_output
      ].freeze

      def initialize(config:)
        @config = config
      end

      def check(text:, rail:, input_text: nil, metadata: {})
        rail_type = rail["type"] || rail[:type]

        case rail_type
        when "token_limit"
          check_token_limit(text, rail)
        when "toxicity"
          check_toxicity(text, rail)
        when "pii_detection"
          check_pii_leakage(text, rail)
        when "hallucination_check"
          check_hallucination(text, rail, input_text)
        when "format_validation"
          check_format(text, rail)
        when "structured_output"
          check_structured_output(text, rail)
        when "regex_filter"
          check_regex_filter(text, rail)
        when "credential_leak"
          check_credential_leak(text, rail)
        else
          { passed: true, rail: rail_type }
        end
      end

      private

      def check_token_limit(text, rail)
        max_tokens = rail["max_tokens"] || @config.max_output_tokens || 50_000
        estimated_tokens = (text.length / 4.0).ceil

        if estimated_tokens > max_tokens
          {
            passed: false,
            rail: "token_limit",
            severity: :warning,
            message: "Output exceeds token limit: ~#{estimated_tokens} tokens (max: #{max_tokens})"
          }
        else
          { passed: true, rail: "token_limit" }
        end
      end

      def check_toxicity(text, rail)
        threshold = rail["threshold"] || @config.toxicity_threshold || 0.7
        toxic_patterns = [
          /\b(kill|murder|attack|destroy|bomb)\s+(you|them|everyone|people)\b/i,
          /\b(hate|despise)\s+(all|every)\s+\w+/i
        ]

        score = toxic_patterns.count { |p| text.match?(p) }.to_f / toxic_patterns.size

        if score >= threshold
          {
            passed: false,
            rail: "toxicity",
            severity: :critical,
            message: "Output toxicity score #{score.round(2)} exceeds threshold #{threshold}"
          }
        else
          { passed: true, rail: "toxicity" }
        end
      end

      def check_pii_leakage(text, rail)
        sensitivity = rail["sensitivity"] || @config.pii_sensitivity || 0.8
        detections = []

        detections << "email" if text.match?(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
        detections << "phone" if text.match?(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/)
        detections << "ssn" if text.match?(/\b\d{3}-\d{2}-\d{4}\b/)
        detections << "credit_card" if text.match?(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/)

        if detections.any?
          {
            passed: false,
            rail: "pii_detection",
            severity: sensitivity >= 0.8 ? :critical : :warning,
            message: "PII detected in output: #{detections.join(', ')}",
            details: { pii_types: detections }
          }
        else
          { passed: true, rail: "pii_detection" }
        end
      end

      def check_hallucination(text, rail, input_text)
        return { passed: true, rail: "hallucination_check" } unless input_text

        confidence_phrases = [
          /I(?:'m|\s+am|\s+'m) (?:100%|absolutely|completely) (?:sure|certain|confident)/i,
          /(?:definitely|undoubtedly|without doubt) (?:true|correct|right)/i
        ]

        has_overconfidence = confidence_phrases.any? { |p| text.match?(p) }

        if has_overconfidence
          {
            passed: false,
            rail: "hallucination_check",
            severity: :warning,
            message: "Output contains overconfident claims that may indicate hallucination"
          }
        else
          { passed: true, rail: "hallucination_check" }
        end
      end

      def check_format(text, rail)
        expected_format = rail["format"]
        return { passed: true, rail: "format_validation" } unless expected_format

        valid = case expected_format
                when "json"
                  begin
                    JSON.parse(text)
                    true
                  rescue JSON::ParserError
                    false
                  end
                when "markdown"
                  text.include?("#") || text.include?("- ") || text.include?("```")
                else
                  true
                end

        if valid
          { passed: true, rail: "format_validation" }
        else
          {
            passed: false,
            rail: "format_validation",
            severity: :warning,
            message: "Output does not match expected format: #{expected_format}"
          }
        end
      end

      def check_regex_filter(text, rail)
        patterns = rail["patterns"] || []
        matched = patterns.find { |p| text.match?(Regexp.new(p, Regexp::IGNORECASE)) }

        if matched
          {
            passed: false,
            rail: "regex_filter",
            severity: (rail["severity"] || "warning").to_sym,
            message: "Output matched blocked pattern"
          }
        else
          { passed: true, rail: "regex_filter" }
        end
      end

      def check_structured_output(text, rail)
        schema = rail["schema"] || rail[:schema]
        return { passed: true, rail: "structured_output" } unless schema

        # Parse the output as JSON
        parsed = begin
          JSON.parse(text)
        rescue JSON::ParserError
          # Try to extract JSON from markdown code blocks
          json_match = text.match(/```(?:json)?\s*\n?(.*?)\n?```/m)
          if json_match
            begin
              JSON.parse(json_match[1])
            rescue JSON::ParserError
              nil
            end
          end
        end

        unless parsed
          return {
            passed: false,
            rail: "structured_output",
            severity: :warning,
            message: "Output is not valid JSON",
            details: { expected_schema: schema }
          }
        end

        # Validate against JSON Schema
        errors = validate_json_schema(parsed, schema)

        if errors.empty?
          { passed: true, rail: "structured_output", details: { parsed: parsed } }
        else
          {
            passed: false,
            rail: "structured_output",
            severity: :warning,
            message: "Output does not match schema: #{errors.first(3).join('; ')}",
            details: { errors: errors, parsed: parsed, expected_schema: schema }
          }
        end
      end

      def validate_json_schema(data, schema)
        errors = []
        schema_type = schema["type"]

        case schema_type
        when "object"
          unless data.is_a?(Hash)
            return ["Expected object, got #{data.class.name.downcase}"]
          end

          # Check required properties
          required = schema["required"] || []
          required.each do |prop|
            errors << "Missing required property: #{prop}" unless data.key?(prop)
          end

          # Validate property types
          properties = schema["properties"] || {}
          properties.each do |prop_name, prop_schema|
            next unless data.key?(prop_name)

            prop_errors = validate_property_type(data[prop_name], prop_schema, prop_name)
            errors.concat(prop_errors)
          end
        when "array"
          unless data.is_a?(Array)
            return ["Expected array, got #{data.class.name.downcase}"]
          end
        end

        errors
      end

      def validate_property_type(value, prop_schema, prop_name)
        expected_type = prop_schema["type"]
        return [] unless expected_type

        valid = case expected_type
                when "string" then value.is_a?(String)
                when "number", "integer" then value.is_a?(Numeric)
                when "boolean" then [true, false].include?(value)
                when "array" then value.is_a?(Array)
                when "object" then value.is_a?(Hash)
                else true
                end

        if valid
          # Check enum constraint
          if prop_schema["enum"] && !prop_schema["enum"].include?(value)
            return ["Property '#{prop_name}' must be one of: #{prop_schema['enum'].join(', ')}"]
          end
          []
        else
          ["Property '#{prop_name}' expected #{expected_type}, got #{value.class.name.downcase}"]
        end
      end

      def check_credential_leak(text, _rail)
        credential_patterns = [
          /(?:api[_-]?key|apikey)\s*[:=]\s*\S{20,}/i,
          /(?:secret|password|passwd|pwd)\s*[:=]\s*\S{8,}/i,
          /(?:bearer|token)\s+[A-Za-z0-9\-_.~+\/]{20,}/i,
          /-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----/,
          /ghp_[A-Za-z0-9]{36}/,
          /sk-[A-Za-z0-9]{48}/
        ]

        matched = credential_patterns.any? { |p| text.match?(p) }

        if matched
          {
            passed: false,
            rail: "credential_leak",
            severity: :critical,
            message: "Potential credential or secret detected in output"
          }
        else
          { passed: true, rail: "credential_leak" }
        end
      end
    end
  end
end
