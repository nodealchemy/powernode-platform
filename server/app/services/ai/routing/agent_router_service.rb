# frozen_string_literal: true

module Ai
  module Routing
    # Routes tasks to the most appropriate agent based on capabilities,
    # skills, historical performance, and trust scores.
    #
    # Extends TaskComplexityClassifierService with agent-specific routing.
    class AgentRouterService
      attr_reader :account

      def initialize(account:)
        @account = account
        @complexity_classifier = TaskComplexityClassifierService.new(account: account)
        @capability_service = Ai::Autonomy::CapabilityMatrixService.new(account: account)
      end

      # Route a task to the best available agent
      # @param task [String] task description
      # @param account [Account] the account
      # @return [Hash] { agent_id:, confidence:, reasoning:, alternatives: }
      def route(task:)
        candidates = account.ai_agents.where(status: "active").includes(:provider)
        return no_agent_available if candidates.empty?

        # Classify task complexity
        complexity = @complexity_classifier.classify_preview(
          task_type: "agent_task",
          messages: [{ role: "user", content: task }],
          tools: [],
          context: {}
        )

        # Score each candidate
        scored = candidates.map do |agent|
          score = calculate_agent_score(agent, task, complexity)
          { agent: agent, score: score }
        end.sort_by { |s| -s[:score][:total] }

        best = scored.first
        alternatives = scored[1..2]&.map { |s| { agent_id: s[:agent].id, score: s[:score][:total].round(3) } } || []

        {
          agent_id: best[:agent].id,
          agent_name: best[:agent].name,
          confidence: best[:score][:total].round(3),
          reasoning: best[:score][:breakdown],
          complexity: complexity,
          alternatives: alternatives
        }
      end

      private

      def calculate_agent_score(agent, task, complexity)
        scores = {}

        # 1. Capability match (0.3 weight)
        capability_result = @capability_service.check(agent: agent, action_type: "execute_tool")
        scores[:capability] = case capability_result
                              when :allowed then 1.0
                              when :requires_approval then 0.5
                              else 0.0
                              end

        # 2. Trust score (0.25 weight)
        trust = Ai::AgentTrustScore.find_by(agent_id: agent.id)
        scores[:trust] = trust ? trust.overall_score : 0.3

        # 3. Skill match (0.25 weight) — semantic similarity between task and agent description
        scores[:skill] = calculate_skill_match(agent, task)

        # 4. Historical performance (0.1 weight)
        scores[:performance] = calculate_performance_score(agent)

        # 5. Cost efficiency (0.1 weight) — prefer lower-cost agents for simpler tasks
        scores[:cost] = calculate_cost_score(agent, complexity)

        weights = { capability: 0.3, trust: 0.25, skill: 0.25, performance: 0.1, cost: 0.1 }
        total = weights.sum { |dim, w| (scores[dim] || 0.0) * w }

        {
          total: total,
          breakdown: scores.transform_values { |v| v.round(3) }
        }
      end

      def calculate_skill_match(agent, task)
        # Check agent capabilities/description for keyword overlap
        agent_text = [
          agent.name, agent.description, agent.system_prompt,
          agent.capabilities&.join(" ")
        ].compact.join(" ").downcase

        task_words = task.downcase.split(/\s+/).reject { |w| w.length < 4 }.uniq
        return 0.3 if task_words.empty?

        matches = task_words.count { |w| agent_text.include?(w) }
        [matches.to_f / task_words.size, 1.0].min
      end

      def calculate_performance_score(agent)
        recent = Ai::AgentExecution
          .where(ai_agent_id: agent.id, status: "completed")
          .where("created_at > ?", 30.days.ago)
          .count

        total = Ai::AgentExecution
          .where(ai_agent_id: agent.id)
          .where("created_at > ?", 30.days.ago)
          .count

        return 0.5 if total.zero?

        (recent.to_f / total).round(3)
      end

      def calculate_cost_score(agent, complexity)
        # Prefer cheaper agents for simpler tasks
        complexity_score = complexity[:complexity_score] || 0.5
        tier = complexity[:recommended_tier] || "standard"

        case tier
        when "economy"
          agent.model.to_s.match?(/mini|small|haiku|flash/) ? 1.0 : 0.5
        when "premium"
          agent.model.to_s.match?(/opus|o1|pro/) ? 1.0 : 0.7
        else
          0.7
        end
      end

      def no_agent_available
        {
          agent_id: nil,
          confidence: 0.0,
          reasoning: { error: "No active agents available" },
          alternatives: []
        }
      end
    end
  end
end
