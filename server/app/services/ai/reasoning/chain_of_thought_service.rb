# frozen_string_literal: true

module Ai
  module Reasoning
    # Performs structured chain-of-thought reasoning via LLM.
    #
    # Asks the model to reason step-by-step about a task and returns
    # a structured result with numbered reasoning steps, a final
    # conclusion, and a confidence score.
    #
    # Usage:
    #   service = Ai::Reasoning::ChainOfThoughtService.new(account: account)
    #   result  = service.reason(
    #     task:       "Determine the optimal caching strategy",
    #     context:    "We have 10k RPM and 2GB Redis",
    #     llm_client: client,
    #     model:      "gpt-4.1"
    #   )
    #   result[:reasoning_steps]  # => [{ step_number: 1, thought: "...", ... }, ...]
    #   result[:conclusion]       # => "Use write-through caching with 5-min TTL"
    #   result[:confidence]       # => 0.85
    #
    class ChainOfThoughtService
      SYSTEM_PROMPT = <<~PROMPT
        You are a rigorous analytical reasoner. When given a task, break your
        thinking into explicit, numbered steps. For each step provide:
        - Your thought process
        - Supporting evidence or assumptions
        - The conclusion drawn from that step

        After all steps, provide a final conclusion and your overall confidence
        (0.0 = no confidence, 1.0 = absolute certainty).

        Respond ONLY with valid JSON matching the requested schema.
      PROMPT

      REASONING_SCHEMA = {
        name: "chain_of_thought",
        schema: {
          type: "object",
          properties: {
            reasoning_steps: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  step_number: { type: "integer" },
                  thought: { type: "string" },
                  evidence: { type: "string" },
                  conclusion: { type: "string" }
                },
                required: %w[step_number thought evidence conclusion]
              }
            },
            final_conclusion: { type: "string" },
            confidence: { type: "number", minimum: 0.0, maximum: 1.0 }
          },
          required: %w[reasoning_steps final_conclusion confidence]
        }
      }.freeze

      def initialize(account:)
        @account = account
      end

      # Perform chain-of-thought reasoning about a task.
      #
      # @param task       [String]           the task or question to reason about
      # @param context    [String, nil]      optional background context
      # @param llm_client [Ai::Llm::Client]  LLM client instance
      # @param model      [String]           model identifier
      # @param opts       [Hash]             additional options forwarded to the LLM
      # @return [Hash] { reasoning_steps: Array, conclusion: String, confidence: Float }
      def reason(task:, context: nil, llm_client:, model:, **opts)
        messages = build_messages(task, context)

        response = llm_client.complete_structured(
          messages: messages,
          schema: REASONING_SCHEMA,
          model: model,
          system_prompt: SYSTEM_PROMPT,
          **opts
        )

        parse_response(response)
      rescue StandardError => e
        Rails.logger.error("[ChainOfThoughtService] Reasoning failed: #{e.message}")
        fallback_result(task, e)
      end

      # Format reasoning steps as a human-readable string suitable for
      # injecting into subsequent LLM messages.
      #
      # @param reasoning_result [Hash] result from #reason
      # @return [String]
      def format_reasoning_for_injection(reasoning_result)
        lines = reasoning_result[:reasoning_steps].map do |step|
          "Step #{step[:step_number]}: #{step[:thought]}\n" \
            "  Evidence: #{step[:evidence]}\n" \
            "  Conclusion: #{step[:conclusion]}"
        end

        lines << "\nFinal Conclusion (confidence: #{reasoning_result[:confidence]}): " \
                 "#{reasoning_result[:conclusion]}"

        lines.join("\n\n")
      end

      private

      def build_messages(task, context)
        user_content = "Task: #{task}"
        user_content = "Context: #{context}\n\n#{user_content}" if context.present?

        [{ role: "user", content: user_content }]
      end

      def parse_response(response)
        parsed = JSON.parse(response.content, symbolize_names: true)

        {
          reasoning_steps: Array(parsed[:reasoning_steps]).map do |step|
            {
              step_number: step[:step_number].to_i,
              thought: step[:thought].to_s,
              evidence: step[:evidence].to_s,
              conclusion: step[:conclusion].to_s
            }
          end,
          conclusion: parsed[:final_conclusion].to_s,
          confidence: parsed[:confidence].to_f.clamp(0.0, 1.0)
        }
      end

      def fallback_result(task, error)
        {
          reasoning_steps: [],
          conclusion: "Reasoning failed for task: #{task} (#{error.class})",
          confidence: 0.0
        }
      end
    end
  end
end
