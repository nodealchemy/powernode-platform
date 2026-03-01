# frozen_string_literal: true

module Ai
  module Reasoning
    # STAR (Situation-Task-Action-Result) structured reasoning service.
    #
    # Based on the finding that structured reasoning scaffolding (STAR)
    # dramatically outperforms context injection alone for implicit
    # constraint reasoning tasks. The critical mechanism is the Task step:
    # forcing explicit goal articulation before reasoning begins surfaces
    # implicit constraints that models otherwise skip.
    #
    # Usage:
    #   service = Ai::Reasoning::StarReasoningService.new(account: account)
    #   result  = service.reason(
    #     task:       "Build user authentication module",
    #     context:    "Rails API with JWT tokens and Devise",
    #     llm_client: client,
    #     model:      "gpt-4.1"
    #   )
    #   result[:task][:implicit_constraints]  # => ["Must handle token expiry", ...]
    #   result[:confidence]                   # => 0.87
    #
    class StarReasoningService
      SYSTEM_PROMPT = <<~PROMPT
        You are a rigorous analytical reasoner using the STAR framework.
        Reason through the given task in four sequential phases:

        1. **Situation** — Analyze the current context, constraints, and relevant factors.
        2. **Task** — CRITICAL: Before taking any action, explicitly articulate the goal.
           Identify implicit constraints that are not stated but must be satisfied.
           Define clear success criteria. This step surfaces hidden requirements.
        3. **Action** — Plan concrete steps to achieve the goal, explain your rationale,
           and note alternatives you considered and why you rejected them.
        4. **Result** — Describe the expected outcome, identify risks, and specify
           how to verify the result is correct.

        The Task phase is the most important — spend the most effort there.
        Respond ONLY with valid JSON matching the requested schema.
      PROMPT

      STAR_SCHEMA = {
        name: "star_reasoning",
        schema: {
          type: "object",
          properties: {
            situation: {
              type: "object",
              properties: {
                analysis: { type: "string" },
                constraints: { type: "array", items: { type: "string" } },
                context_factors: { type: "array", items: { type: "string" } }
              },
              required: %w[analysis constraints context_factors]
            },
            task: {
              type: "object",
              properties: {
                goal: { type: "string" },
                implicit_constraints: { type: "array", items: { type: "string" } },
                success_criteria: { type: "array", items: { type: "string" } }
              },
              required: %w[goal implicit_constraints success_criteria]
            },
            action: {
              type: "object",
              properties: {
                steps: { type: "array", items: { type: "string" } },
                rationale: { type: "string" },
                alternatives_considered: { type: "array", items: { type: "string" } }
              },
              required: %w[steps rationale alternatives_considered]
            },
            result: {
              type: "object",
              properties: {
                expected_outcome: { type: "string" },
                risks: { type: "array", items: { type: "string" } },
                verification_approach: { type: "string" }
              },
              required: %w[expected_outcome risks verification_approach]
            },
            confidence: { type: "number", minimum: 0.0, maximum: 1.0 }
          },
          required: %w[situation task action result confidence]
        }
      }.freeze

      def initialize(account:)
        @account = account
      end

      # Perform STAR reasoning about a task.
      #
      # @param task       [String]           the task or question to reason about
      # @param context    [String, nil]      optional background context
      # @param llm_client [WorkerLlmClient]  LLM client instance
      # @param model      [String]           model identifier
      # @param opts       [Hash]             additional options forwarded to the LLM
      # @return [Hash] structured STAR result with confidence score
      def reason(task:, context: nil, llm_client:, model:, **opts)
        messages = build_messages(task, context)

        response = llm_client.complete_structured(
          messages: messages,
          schema: STAR_SCHEMA,
          model: model,
          system_prompt: SYSTEM_PROMPT,
          **opts
        )

        parse_response(response)
      rescue StandardError => e
        Rails.logger.error("[StarReasoningService] Reasoning failed: #{e.message}")
        fallback_result(task, e)
      end

      # Format STAR reasoning as a human-readable string suitable for
      # injecting into subsequent LLM messages.
      #
      # @param star_result [Hash] result from #reason
      # @return [String]
      def format_reasoning_for_injection(star_result)
        sections = []

        # Situation
        sit = star_result[:situation]
        sections << "## Situation\n#{sit[:analysis]}"
        sections << "Constraints: #{sit[:constraints].join('; ')}" if sit[:constraints].present?
        sections << "Context factors: #{sit[:context_factors].join('; ')}" if sit[:context_factors].present?

        # Task (the critical section)
        tsk = star_result[:task]
        sections << "## Task (Goal Articulation)\nGoal: #{tsk[:goal]}"
        sections << "Implicit constraints: #{tsk[:implicit_constraints].join('; ')}" if tsk[:implicit_constraints].present?
        sections << "Success criteria: #{tsk[:success_criteria].join('; ')}" if tsk[:success_criteria].present?

        # Action
        act = star_result[:action]
        steps_text = act[:steps].each_with_index.map { |s, i| "#{i + 1}. #{s}" }.join("\n")
        sections << "## Action\n#{steps_text}\nRationale: #{act[:rationale]}"
        sections << "Alternatives considered: #{act[:alternatives_considered].join('; ')}" if act[:alternatives_considered].present?

        # Result
        res = star_result[:result]
        sections << "## Expected Result\n#{res[:expected_outcome]}"
        sections << "Risks: #{res[:risks].join('; ')}" if res[:risks].present?
        sections << "Verification: #{res[:verification_approach]}"

        sections << "\nConfidence: #{star_result[:confidence]}"

        sections.join("\n\n")
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
          situation: parse_situation(parsed[:situation]),
          task: parse_task(parsed[:task]),
          action: parse_action(parsed[:action]),
          result: parse_result(parsed[:result]),
          confidence: parsed[:confidence].to_f.clamp(0.0, 1.0)
        }
      end

      def parse_situation(sit)
        {
          analysis: sit[:analysis].to_s,
          constraints: Array(sit[:constraints]).map(&:to_s),
          context_factors: Array(sit[:context_factors]).map(&:to_s)
        }
      end

      def parse_task(tsk)
        {
          goal: tsk[:goal].to_s,
          implicit_constraints: Array(tsk[:implicit_constraints]).map(&:to_s),
          success_criteria: Array(tsk[:success_criteria]).map(&:to_s)
        }
      end

      def parse_action(act)
        {
          steps: Array(act[:steps]).map(&:to_s),
          rationale: act[:rationale].to_s,
          alternatives_considered: Array(act[:alternatives_considered]).map(&:to_s)
        }
      end

      def parse_result(res)
        {
          expected_outcome: res[:expected_outcome].to_s,
          risks: Array(res[:risks]).map(&:to_s),
          verification_approach: res[:verification_approach].to_s
        }
      end

      def fallback_result(task, error)
        {
          situation: { analysis: "", constraints: [], context_factors: [] },
          task: { goal: "", implicit_constraints: [], success_criteria: [] },
          action: { steps: [], rationale: "", alternatives_considered: [] },
          result: { expected_outcome: "", risks: [], verification_approach: "" },
          confidence: 0.0
        }
      end
    end
  end
end
