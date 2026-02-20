# frozen_string_literal: true

module Ai
  module Guardrails
    class Pipeline
      class GuardrailViolation < StandardError
        attr_reader :rail_name, :severity, :details

        def initialize(message, rail_name:, severity: :warning, details: {})
          @rail_name = rail_name
          @severity = severity
          @details = details
          super(message)
        end
      end

      def initialize(account:, agent: nil)
        @account = account
        @agent = agent
        @config = load_config
      end

      def check_input(text:, metadata: {})
        return allow_result unless @config&.is_active?

        violations = []
        input_rail = InputRail.new(config: @config, account: @account)

        @config.input_rails.each do |rail_spec|
          result = input_rail.check(text: text, rail: rail_spec, metadata: metadata)
          violations << result unless result[:passed]
        end

        record_and_build_result(violations, stage: :input)
      end

      def check_output(text:, input_text: nil, metadata: {})
        return allow_result unless @config&.is_active?

        violations = []
        output_rail = OutputRail.new(config: @config, account: @account)

        @config.output_rails.each do |rail_spec|
          result = output_rail.check(text: text, rail: rail_spec, input_text: input_text, metadata: metadata)
          violations << result unless result[:passed]
        end

        record_and_build_result(violations, stage: :output)
      end

      def check_retrieval(documents:, query: nil, metadata: {})
        return allow_result unless @config&.is_active?

        violations = []

        @config.retrieval_rails.each do |rail_spec|
          documents.each_with_index do |doc, idx|
            content = doc.is_a?(Hash) ? (doc[:content] || doc["content"]) : doc.to_s
            result = check_retrieval_document(content: content, rail: rail_spec, index: idx, query: query)
            violations << result unless result[:passed]
          end
        end

        record_and_build_result(violations, stage: :retrieval)
      end

      private

      def load_config
        config = Ai::GuardrailConfig.active.for_agent(@agent&.id).first if @agent
        config || Ai::GuardrailConfig.active.global.where(account: @account).first
      end

      def check_retrieval_document(content:, rail:, index:, query:)
        rail_type = rail["type"] || rail[:type]

        case rail_type
        when "relevance_check"
          min_relevance = rail["min_relevance"] || 0.3
          { passed: true, rail: rail_type, index: index }
        when "content_filter"
          blocked_patterns = rail["blocked_patterns"] || []
          matched = blocked_patterns.any? { |p| content.match?(Regexp.new(p, Regexp::IGNORECASE)) }
          if matched
            { passed: false, rail: rail_type, index: index, message: "Document #{index} matched blocked pattern" }
          else
            { passed: true, rail: rail_type, index: index }
          end
        else
          { passed: true, rail: rail_type, index: index }
        end
      end

      def record_and_build_result(violations, stage:)
        blocked = violations.any? { |v| v[:severity] == :critical } ||
                  (violations.any? && @config.block_on_failure)

        @config.record_check!(blocked: blocked) if @config

        if violations.empty?
          allow_result
        else
          {
            allowed: !blocked,
            stage: stage,
            violations: violations,
            violation_count: violations.size,
            blocked: blocked
          }
        end
      end

      def allow_result
        { allowed: true, violations: [], violation_count: 0, blocked: false }
      end
    end
  end
end
