# frozen_string_literal: true

module Ai
  module Autonomy
    class GoalDecompositionService
      include Ai::LlmCallable

      MAX_STEPS = 20

      def initialize(account:)
        @account = account
      end

      def decompose(goal)
        return nil unless goal

        agent = goal.agent
        return nil unless agent

        # Build context for decomposition
        context = build_decomposition_context(goal, agent)

        # LLM-based planning via worker proxy
        prompt = build_decomposition_prompt(goal, context)

        response = call_llm(agent: agent, prompt: prompt, max_tokens: 1000, temperature: 0.3)

        return nil unless response&.dig(:content)

        # Parse plan from LLM response
        steps_data = parse_plan_steps(response[:content])
        return nil if steps_data.empty?

        # Determine version
        latest_version = Ai::GoalPlan.for_goal(goal.id).maximum(:version) || 0

        # Create plan
        plan = Ai::GoalPlan.create!(
          account: @account,
          goal: goal,
          agent: agent,
          status: "draft",
          version: latest_version + 1,
          plan_data: { raw_response: response[:content], decomposition_context: context },
          estimated_cost_usd: steps_data.sum { |s| s[:estimated_cost] || 0 },
          estimated_duration_minutes: steps_data.sum { |s| s[:estimated_duration] || 5 }
        )

        # Create steps
        steps_data.each_with_index do |step_data, idx|
          plan.steps.create!(
            step_number: idx + 1,
            step_type: step_data[:type] || "agent_execution",
            description: step_data[:description],
            dependencies: step_data[:dependencies] || [],
            execution_config: step_data[:config] || {},
            estimated_cost_usd: step_data[:estimated_cost],
            estimated_duration_minutes: step_data[:estimated_duration]
          )
        end

        Rails.logger.info("[GoalDecomposition] Created plan #{plan.id} with #{steps_data.size} steps for goal #{goal.id}")
        plan
      rescue StandardError => e
        Rails.logger.warn("[GoalDecomposition] Failed: #{e.message}")
        nil
      end

      def validate(plan)
        errors = []

        # Cost within budget
        if plan.estimated_cost_usd
          agent_budget = Ai::AgentBudget.where(agent_id: plan.ai_agent_id).active.first
          if agent_budget && plan.estimated_cost_usd > agent_budget.remaining_cents / 100.0
            errors << "Estimated cost ($#{plan.estimated_cost_usd}) exceeds agent budget ($#{agent_budget.remaining_cents / 100.0})"
          end
        end

        # Step count limit
        if plan.steps.count > MAX_STEPS
          errors << "Plan has #{plan.steps.count} steps, maximum is #{MAX_STEPS}"
        end

        # DAG acyclicity check
        if has_dependency_cycle?(plan)
          errors << "Plan has circular dependencies"
        end

        # High-risk steps should have human_review
        high_risk_steps = plan.steps.where(step_type: %w[agent_execution workflow_run])
          .where("(execution_config->>'risk_level')::text IN (?)", %w[high critical])
        if high_risk_steps.any? && plan.steps.where(step_type: "human_review").empty?
          errors << "High-risk steps detected without human review checkpoint"
        end

        result = { valid: errors.empty?, errors: errors }
        plan.update!(
          validation_result: result,
          status: errors.empty? ? "validated" : "draft"
        )

        result
      end

      def materialize(plan)
        return nil unless plan.status == "approved"

        plan.start_execution!
        goal = plan.goal

        plan.steps.in_order.each do |step|
          case step.step_type
          when "sub_goal"
            sub_goal = Ai::AgentGoal.create!(
              account: @account,
              agent: goal.agent,
              parent_goal: goal,
              title: step.description,
              goal_type: "improvement",
              status: "pending",
              success_criteria: step.execution_config
            )
            step.update!(sub_goal: sub_goal)
          end
        end

        plan
      end

      def replan(goal, failed_plan:, reflexion: nil)
        context = {
          previous_plan: failed_plan.plan_data,
          failure_reason: failed_plan.validation_result["failure_reason"],
          reflexion: reflexion&.content
        }

        decompose(goal).tap do |new_plan|
          if new_plan
            new_plan.update!(plan_data: new_plan.plan_data.merge("replan_context" => context))
          end
        end
      end

      private

      def build_decomposition_context(goal, agent)
        {
          agent_name: agent.name,
          agent_type: agent.agent_type,
          capabilities: agent.capabilities,
          trust_tier: Ai::AgentTrustScore.find_by(agent_id: agent.id)&.tier || "supervised",
          budget_remaining: Ai::AgentBudget.where(agent_id: agent.id).active.first&.remaining_cents&.to_f&./(100),
          existing_sub_goals: goal.sub_goals.pluck(:title, :status)
        }
      end

      def build_decomposition_prompt(goal, context)
        <<~PROMPT
          Decompose this goal into executable steps (max #{MAX_STEPS}).

          Goal: #{goal.title}
          Description: #{goal.description}
          Type: #{goal.goal_type}
          Success Criteria: #{goal.success_criteria.to_json}

          Agent: #{context[:agent_name]} (#{context[:agent_type]})
          Trust: #{context[:trust_tier]}
          Budget: $#{context[:budget_remaining] || 'unknown'}

          For each step, provide:
          STEP: <number>
          TYPE: agent_execution|workflow_run|observation|human_review|sub_goal
          DESCRIPTION: <what to do>
          DEPENDS_ON: <comma-separated step numbers, or "none">
          EST_MINUTES: <estimated duration>
          EST_COST: <estimated cost in USD>

          Include human_review steps for high-risk operations. Keep steps atomic and ordered by dependency.
        PROMPT
      end

      def parse_plan_steps(response_text)
        steps = []
        current_step = {}

        response_text.each_line do |line|
          line = line.strip
          case line
          when /^STEP:\s*(\d+)/i
            steps << current_step if current_step[:description]
            current_step = { number: ::Regexp.last_match(1).to_i }
          when /^TYPE:\s*(.+)/i
            current_step[:type] = ::Regexp.last_match(1).strip.downcase
          when /^DESCRIPTION:\s*(.+)/i
            current_step[:description] = ::Regexp.last_match(1).strip
          when /^DEPENDS_ON:\s*(.+)/i
            deps = ::Regexp.last_match(1).strip
            current_step[:dependencies] = deps == "none" ? [] : deps.split(",").map(&:strip).map(&:to_i)
          when /^EST_MINUTES:\s*(.+)/i
            current_step[:estimated_duration] = ::Regexp.last_match(1).strip.to_i
          when /^EST_COST:\s*(.+)/i
            current_step[:estimated_cost] = ::Regexp.last_match(1).strip.gsub("$", "").to_f
          end
        end

        steps << current_step if current_step[:description]
        steps.select { |s| s[:description].present? }
      end

      def has_dependency_cycle?(plan)
        adjacency = {}
        plan.steps.each do |step|
          adjacency[step.step_number] = (step.dependencies || []).map(&:to_i)
        end

        visited = {}
        in_stack = {}

        adjacency.each_key do |node|
          return true if dfs_cycle?(node, adjacency, visited, in_stack)
        end

        false
      end

      def dfs_cycle?(node, adjacency, visited, in_stack)
        return false if visited[node]
        return true if in_stack[node]

        in_stack[node] = true

        (adjacency[node] || []).each do |dep|
          return true if dfs_cycle?(dep, adjacency, visited, in_stack)
        end

        in_stack[node] = false
        visited[node] = true
        false
      end
    end
  end
end
