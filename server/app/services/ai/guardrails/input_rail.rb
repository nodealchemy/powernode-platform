# frozen_string_literal: true

module Ai
  module Guardrails
    class InputRail
      BUILT_IN_RAILS = %w[
        token_limit
        prompt_injection
        pii_detection
        topic_restriction
        language_detection
      ].freeze

      def initialize(config:)
        @config = config
      end

      def check(text:, rail:, metadata: {})
        rail_type = rail["type"] || rail[:type]

        case rail_type
        when "token_limit"
          check_token_limit(text, rail)
        when "prompt_injection"
          check_prompt_injection(text, rail)
        when "pii_detection"
          check_pii(text, rail)
        when "topic_restriction"
          check_topic_restriction(text, rail)
        when "language_detection"
          check_language(text, rail)
        when "regex_filter"
          check_regex_filter(text, rail)
        else
          { passed: true, rail: rail_type }
        end
      end

      private

      def check_token_limit(text, rail)
        max_tokens = rail["max_tokens"] || @config.max_input_tokens || 100_000
        estimated_tokens = (text.length / 4.0).ceil

        if estimated_tokens > max_tokens
          {
            passed: false,
            rail: "token_limit",
            severity: :critical,
            message: "Input exceeds token limit: ~#{estimated_tokens} tokens (max: #{max_tokens})"
          }
        else
          { passed: true, rail: "token_limit" }
        end
      end

      def check_prompt_injection(text, rail)
        sensitivity = rail["sensitivity"] || "medium"
        patterns = injection_patterns(sensitivity)

        matched = patterns.find { |p| text.match?(p) }

        if matched
          {
            passed: false,
            rail: "prompt_injection",
            severity: :critical,
            message: "Potential prompt injection detected"
          }
        else
          { passed: true, rail: "prompt_injection" }
        end
      end

      def check_pii(text, rail)
        sensitivity = rail["sensitivity"] || @config.pii_sensitivity || 0.8
        pii_types = rail["pii_types"] || %w[email phone ssn credit_card]

        detections = []
        detections << "email" if pii_types.include?("email") && text.match?(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
        detections << "phone" if pii_types.include?("phone") && text.match?(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/)
        detections << "ssn" if pii_types.include?("ssn") && text.match?(/\b\d{3}-\d{2}-\d{4}\b/)
        detections << "credit_card" if pii_types.include?("credit_card") && text.match?(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/)

        if detections.any?
          {
            passed: false,
            rail: "pii_detection",
            severity: sensitivity >= 0.8 ? :critical : :warning,
            message: "PII detected: #{detections.join(', ')}",
            details: { pii_types: detections }
          }
        else
          { passed: true, rail: "pii_detection" }
        end
      end

      def check_topic_restriction(text, rail)
        blocked_topics = rail["blocked_topics"] || []
        text_lower = text.downcase

        matched = blocked_topics.find { |topic| text_lower.include?(topic.downcase) }

        if matched
          {
            passed: false,
            rail: "topic_restriction",
            severity: :warning,
            message: "Input contains restricted topic: #{matched}"
          }
        else
          { passed: true, rail: "topic_restriction" }
        end
      end

      def check_language(text, _rail)
        # Basic ASCII check — allow through by default
        { passed: true, rail: "language_detection" }
      end

      def check_regex_filter(text, rail)
        patterns = rail["patterns"] || []
        matched = patterns.find { |p| text.match?(Regexp.new(p, Regexp::IGNORECASE)) }

        if matched
          {
            passed: false,
            rail: "regex_filter",
            severity: (rail["severity"] || "warning").to_sym,
            message: "Input matched blocked pattern"
          }
        else
          { passed: true, rail: "regex_filter" }
        end
      end

      def injection_patterns(sensitivity)
        base = [
          /ignore\s+(all\s+)?previous\s+instructions/i,
          /you\s+are\s+now\s+(?:a|an|the)\s+/i,
          /system\s*:\s*you\s+are/i,
          /\]\]\s*>\s*</i
        ]

        if sensitivity == "high"
          base + [
            /pretend\s+(?:you|that)/i,
            /act\s+as\s+(?:if|though)/i,
            /disregard\s+(?:your|the|all)/i,
            /override\s+(?:your|the|all)/i,
            /forget\s+(?:everything|your|all)/i
          ]
        else
          base
        end
      end
    end
  end
end
