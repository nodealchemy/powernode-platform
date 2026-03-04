# frozen_string_literal: true

module Ai
  module Learning
    class ReflexionService
      include Ai::LlmCallable

      MIN_TRUST_TIER = "monitored"
      MIN_COST_FOR_REFLEXION = 0.01
      REFLEXION_COOLDOWN = 30.minutes
      TRUST_TIER_ORDER = %w[supervised monitored trusted autonomous].freeze

      def initialize(account:)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Determine if an execution warrants LLM-based reflexion
      def should_reflect?(execution)
        return false unless execution
        return false unless execution.respond_to?(:status) && execution.status == "failed"

        # Check agent trust tier
        agent = execution.respond_to?(:ai_agent) ? execution.ai_agent : nil
        return false unless agent

        trust_score = Ai::AgentTrustScore.find_by(agent_id: agent.id)
        tier = trust_score&.tier || "supervised"
        return false unless TRUST_TIER_ORDER.index(tier).to_i >= TRUST_TIER_ORDER.index(MIN_TRUST_TIER)

        # Check cost threshold (avoid reflexion on trivial failures)
        cost = execution.respond_to?(:cost_usd) ? execution.cost_usd.to_f : 0
        return false if cost < MIN_COST_FOR_REFLEXION

        # Check cooldown (avoid duplicate reflexions)
        recent_reflexion = Ai::CompoundLearning
          .for_account(@account.id)
          .by_category("reflexion")
          .where("created_at > ?", REFLEXION_COOLDOWN.ago)
          .where("metadata->>'source_execution_id' = ?", execution.id.to_s)
          .exists?

        !recent_reflexion
      end

      # Perform LLM-based reflection on a failed execution
      def reflect_on_failure(execution)
        return nil unless should_reflect?(execution)

        agent = execution.ai_agent
        error_message = execution.respond_to?(:error_message) ? execution.error_message : "Unknown error"
        error_details = execution.respond_to?(:error_details) ? execution.error_details : {}
        input_params = execution.respond_to?(:input_parameters) ? execution.input_parameters : {}

        # Build reflexion prompt
        prompt = build_reflexion_prompt(
          task: input_params,
          error: error_message,
          error_details: error_details,
          agent_name: agent.name
        )

        # Call LLM for reflexion via worker proxy
        response = call_llm(agent: agent, prompt: prompt, max_tokens: 500, temperature: 0.3)

        return nil unless response&.dig(:content)

        # Parse reflexion response
        reflexion_data = parse_reflexion(response[:content])

        # Store as compound learning with reflexion category
        embedding = @embedding_service.generate(reflexion_data[:content])

        learning = Ai::CompoundLearning.create!(
          account: @account,
          source_agent: agent,
          source_execution_id: execution.id,
          category: "reflexion",
          title: "[REFLEXION] #{reflexion_data[:root_cause]&.truncate(100) || error_message.truncate(100)}",
          content: reflexion_data[:content],
          importance_score: 0.7,
          confidence_score: 0.6,
          extraction_method: "reflexion",
          source_execution_successful: false,
          embedding: embedding,
          tags: ["reflexion", reflexion_data[:error_class]].compact,
          metadata: {
            reflexion_type: "failure_analysis",
            error_class: reflexion_data[:error_class],
            root_cause_hypothesis: reflexion_data[:root_cause],
            counterfactual: reflexion_data[:counterfactual],
            reflection_depth: 1,
            source_execution_id: execution.id,
            cost_usd: response[:cost_usd]
          }
        )

        Rails.logger.info("[Reflexion] Created reflexion learning #{learning.id} for execution #{execution.id}")
        learning
      rescue StandardError => e
        Rails.logger.warn("[Reflexion] Failed to reflect: #{e.message}")
        nil
      end

      # Build context from relevant reflexions for a task
      def build_reflexion_context(task_description:, token_budget: 800)
        embedding = @embedding_service.generate(task_description)
        return { context: nil, token_estimate: 0 } unless embedding

        reflexions = Ai::CompoundLearning
          .for_account(@account.id)
          .by_category("reflexion")
          .active
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .limit(10)
          .to_a
          .select { |e| e.neighbor_distance <= 0.5 }

        return { context: nil, token_estimate: 0 } if reflexions.empty?

        char_budget = token_budget * 4
        lines = ["### Reflexion Warnings"]
        used_chars = lines.first.length + 2

        reflexions.each do |r|
          root_cause = r.metadata&.dig("root_cause_hypothesis") || "unknown"
          counterfactual = r.metadata&.dig("counterfactual")
          line = "- [REFLEXION] #{r.title}: Root cause: #{root_cause}"
          line += " | Instead: #{counterfactual}" if counterfactual.present?
          break if used_chars + line.length > char_budget

          lines << line
          used_chars += line.length + 1
          r.record_access!
        end

        return { context: nil, token_estimate: 0 } if lines.size == 1

        {
          context: lines.join("\n"),
          token_estimate: (used_chars / 4.0).ceil
        }
      end

      private

      def build_reflexion_prompt(task:, error:, error_details:, agent_name:)
        <<~PROMPT
          You are analyzing a failed AI agent execution. Provide a structured reflection.

          Agent: #{agent_name}
          Task: #{task.to_json.truncate(500)}
          Error: #{error}
          Details: #{error_details.to_json.truncate(300)}

          Respond in this exact format:
          ROOT_CAUSE: <one-sentence root cause hypothesis>
          ERROR_CLASS: <category: input_error|configuration|timeout|resource_limit|logic_error|external_dependency|permission|unknown>
          COUNTERFACTUAL: <what should have been done differently>
          LEARNING: <actionable lesson for future similar tasks, 1-2 sentences>
        PROMPT
      end

      def parse_reflexion(response_text)
        root_cause = response_text[/ROOT_CAUSE:\s*(.+?)(?:\n|$)/i, 1]&.strip
        error_class = response_text[/ERROR_CLASS:\s*(.+?)(?:\n|$)/i, 1]&.strip
        counterfactual = response_text[/COUNTERFACTUAL:\s*(.+?)(?:\n|$)/i, 1]&.strip
        learning = response_text[/LEARNING:\s*(.+?)(?:\n|$)/i, 1]&.strip

        content = [
          "Root cause: #{root_cause || 'unknown'}",
          "Error class: #{error_class || 'unknown'}",
          "Counterfactual: #{counterfactual || 'N/A'}",
          "Learning: #{learning || response_text.truncate(200)}"
        ].join("\n")

        {
          root_cause: root_cause,
          error_class: error_class,
          counterfactual: counterfactual,
          content: content
        }
      end
    end
  end
end
