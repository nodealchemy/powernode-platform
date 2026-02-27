# frozen_string_literal: true

module Ai
  module Reasoning
    # Post-execution self-critique service.
    #
    # Asks an LLM to evaluate the quality of a prior output, surface issues,
    # suggest improvements, and decide whether the task should be retried.
    #
    # Usage:
    #   service = Ai::Reasoning::ReflectionService.new(account: account)
    #   result  = service.reflect(
    #     task:       "Write a migration for users table",
    #     output:     generated_migration_code,
    #     context:    { agent_id: agent.id },
    #     llm_client: client,
    #     model:      "gpt-4.1"
    #   )
    #   result[:should_retry]   # => false
    #   result[:quality_score]  # => 0.82
    #
    class ReflectionService
      SYSTEM_PROMPT = <<~PROMPT
        You are a meticulous quality reviewer. Given a task description and the
        output produced, perform a self-critique. Evaluate:
        - Overall quality (0.0 = unusable, 1.0 = flawless)
        - Specific issues found
        - Concrete improvements that could be made
        - Whether the output should be retried entirely

        If known improvement areas are provided, pay special attention to those.
        Respond ONLY with valid JSON matching the requested schema.
      PROMPT

      REFLECTION_SCHEMA = {
        name: "reflection",
        schema: {
          type: "object",
          properties: {
            quality_score: { type: "number", minimum: 0.0, maximum: 1.0 },
            issues: {
              type: "array",
              items: { type: "string" }
            },
            improvements: {
              type: "array",
              items: { type: "string" }
            },
            should_retry: { type: "boolean" }
          },
          required: %w[quality_score issues improvements should_retry]
        }
      }.freeze

      def initialize(account:)
        @account = account
      end

      # Reflect on a task's output quality.
      #
      # @param task       [String]           original task description
      # @param output     [String]           the output to critique
      # @param context    [Hash]             optional context (may include :agent_id)
      # @param llm_client [WorkerLlmClient]  LLM client instance
      # @param model      [String]           model identifier
      # @param opts       [Hash]             additional options forwarded to the LLM
      # @return [Hash] { quality_score: Float, issues: Array, improvements: Array, should_retry: Boolean }
      def reflect(task:, output:, context: {}, llm_client:, model:, **opts)
        improvement_areas = fetch_improvement_areas(context[:agent_id])
        messages = build_messages(task, output, improvement_areas)

        response = llm_client.complete_structured(
          messages: messages,
          schema: REFLECTION_SCHEMA,
          model: model,
          system_prompt: SYSTEM_PROMPT,
          **opts
        )

        parse_response(response)
      rescue StandardError => e
        Rails.logger.error("[ReflectionService] Reflection failed: #{e.message}")
        fallback_result(e)
      end

      # Record a reflection result as a span on an execution trace.
      #
      # @param execution_trace   [Ai::ExecutionTrace] the parent trace
      # @param reflection_result [Hash]               result from #reflect
      # @return [Ai::ExecutionTraceSpan, nil]
      def record_reflection_span(execution_trace, reflection_result)
        now = Time.current

        execution_trace.execution_trace_spans.create!(
          span_id: SecureRandom.uuid,
          name: "self_reflection",
          span_type: "reflection",
          status: "completed",
          started_at: now,
          completed_at: now,
          duration_ms: 0,
          input_data: { quality_score: reflection_result[:quality_score] },
          output_data: {
            issues: reflection_result[:issues],
            improvements: reflection_result[:improvements],
            should_retry: reflection_result[:should_retry]
          },
          metadata: { source: "ReflectionService" }
        )
      rescue StandardError => e
        Rails.logger.error("[ReflectionService] Failed to record span: #{e.message}")
        nil
      end

      private

      def build_messages(task, output, improvement_areas)
        user_content = +"Task: #{task}\n\nOutput:\n#{output}"

        if improvement_areas.present?
          user_content << "\n\nKnown improvement areas to check against:\n"
          user_content << improvement_areas.map { |area| "- #{area}" }.join("\n")
        end

        [{ role: "user", content: user_content }]
      end

      def fetch_improvement_areas(agent_id)
        return [] if agent_id.blank?

        pool = Ai::MemoryPool.find_by(account: @account, pool_type: "default")
        return [] unless pool

        data = pool.read_data("agent.#{agent_id}.improvement_areas")
        return [] unless data.is_a?(Array)

        data
      rescue StandardError => e
        Rails.logger.warn("[ReflectionService] Could not fetch improvement areas: #{e.message}")
        []
      end

      def parse_response(response)
        parsed = JSON.parse(response.content, symbolize_names: true)

        {
          quality_score: parsed[:quality_score].to_f.clamp(0.0, 1.0),
          issues: Array(parsed[:issues]).map(&:to_s),
          improvements: Array(parsed[:improvements]).map(&:to_s),
          should_retry: parsed[:should_retry] == true
        }
      end

      def fallback_result(error)
        {
          quality_score: 0.0,
          issues: ["Reflection failed: #{error.message}"],
          improvements: [],
          should_retry: false
        }
      end
    end
  end
end
