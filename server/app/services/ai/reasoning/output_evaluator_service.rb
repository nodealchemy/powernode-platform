# frozen_string_literal: true

module Ai
  module Reasoning
    # Independent output evaluator that judges quality using a separate
    # LLM call with distinct temperature settings.
    #
    # Returns a verdict ("pass", "revise", "reject") along with per-criteria
    # scores and actionable feedback. Callers use the verdict to decide
    # whether to accept, re-execute with feedback, or abort.
    #
    # Usage:
    #   evaluator = Ai::Reasoning::OutputEvaluatorService.new(account: account)
    #   result    = evaluator.evaluate(
    #     task:       "Generate a Kubernetes deployment manifest",
    #     output:     generated_yaml,
    #     criteria:   %w[completeness accuracy],
    #     llm_client: client,
    #     model:      "gpt-4.1"
    #   )
    #   result[:verdict]   # => "pass" | "revise" | "reject"
    #   result[:scores]    # => { completeness: 0.9, accuracy: 0.85, ... }
    #   result[:feedback]  # => "Missing resource limits on the container spec."
    #
    class OutputEvaluatorService
      EVALUATION_TEMPERATURE = 0.3
      DEFAULT_CRITERIA = %w[completeness accuracy format_compliance safety].freeze
      VALID_VERDICTS = %w[pass revise reject].freeze

      SYSTEM_PROMPT = <<~PROMPT
        You are an impartial output evaluator. Given a task and its output,
        evaluate the output against the provided criteria. For each criterion
        assign a score from 0.0 (completely fails) to 1.0 (perfectly meets).

        Determine a verdict:
        - "pass"   — output meets all criteria acceptably (all scores >= 0.6)
        - "revise" — output has fixable issues (some scores < 0.6 but >= 0.3)
        - "reject" — output is fundamentally flawed (any score < 0.3)

        Provide specific, actionable feedback explaining your verdict.
        Respond ONLY with valid JSON matching the requested schema.
      PROMPT

      def initialize(account:)
        @account = account
      end

      # Evaluate an output against quality criteria.
      #
      # @param task       [String]           original task description
      # @param output     [String]           the output to evaluate
      # @param criteria   [Array<String>]    evaluation criteria (defaults to standard set)
      # @param llm_client [Ai::Llm::Client]  LLM client instance
      # @param model      [String]           model identifier
      # @param opts       [Hash]             additional options forwarded to the LLM
      # @return [Hash] { verdict: String, scores: Hash, feedback: String }
      def evaluate(task:, output:, criteria: [], llm_client:, model:, **opts)
        active_criteria = criteria.presence || DEFAULT_CRITERIA
        messages = build_messages(task, output, active_criteria)
        schema = build_schema(active_criteria)

        response = llm_client.complete_structured(
          messages: messages,
          schema: schema,
          model: model,
          system_prompt: SYSTEM_PROMPT,
          temperature: EVALUATION_TEMPERATURE,
          **opts
        )

        parse_response(response, active_criteria)
      rescue StandardError => e
        Rails.logger.error("[OutputEvaluatorService] Evaluation failed: #{e.message}")
        fallback_result(e)
      end

      private

      def build_messages(task, output, criteria)
        user_content = <<~MSG
          Task: #{task}

          Output to evaluate:
          #{output}

          Evaluate against these criteria: #{criteria.join(', ')}
        MSG

        [{ role: "user", content: user_content }]
      end

      def build_schema(criteria)
        score_properties = criteria.each_with_object({}) do |criterion, hash|
          hash[criterion] = { type: "number", minimum: 0.0, maximum: 1.0 }
        end

        {
          name: "output_evaluation",
          schema: {
            type: "object",
            properties: {
              verdict: { type: "string", enum: VALID_VERDICTS },
              scores: {
                type: "object",
                properties: score_properties,
                required: criteria
              },
              feedback: { type: "string" }
            },
            required: %w[verdict scores feedback]
          }
        }
      end

      def parse_response(response, criteria)
        parsed = JSON.parse(response.content, symbolize_names: true)
        verdict = parsed[:verdict].to_s

        # Normalize verdict to a valid value
        verdict = "revise" unless VALID_VERDICTS.include?(verdict)

        scores = criteria.each_with_object({}) do |criterion, hash|
          key = criterion.to_sym
          hash[key] = (parsed.dig(:scores, key) || 0.0).to_f.clamp(0.0, 1.0)
        end

        {
          verdict: verdict,
          scores: scores,
          feedback: parsed[:feedback].to_s
        }
      end

      def fallback_result(error)
        {
          verdict: "revise",
          scores: {},
          feedback: "Evaluation failed: #{error.message}"
        }
      end
    end
  end
end
