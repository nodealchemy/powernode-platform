# frozen_string_literal: true

module Ai
  module Autonomy
    class DutyCycleService
      MAX_ACTIONS_PER_CYCLE = 3
      DEFAULT_PROACTIVE_RATIO = 0.3
      MAX_DAILY_ACTIONS = 50
      DECISION_PRIORITY_ORDER = %w[
        urgent_reaction
        approval_queue
        active_goal_progress
        proactive_improvement
        communication
        idle
      ].freeze

      attr_reader :account, :agent, :ralph_loop

      def initialize(account:, agent:, ralph_loop:)
        @account = account
        @agent = agent
        @ralph_loop = ralph_loop
      end

      # Run one full OODA duty cycle iteration.
      #
      # @return [Hash] { actions_taken: Integer, observations_collected: Integer, decisions: Array }
      def execute_cycle
        config = ralph_loop.duty_cycle_config
        max_actions = config["max_actions_per_cycle"] || MAX_ACTIONS_PER_CYCLE

        # Phase 1: OBSERVE — collect signals from sensors
        observations = observe(config)

        # Phase 2: ORIENT — rank and filter observations against goals
        prioritized = orient(observations)

        # Phase 3: DECIDE — LLM-based action selection
        decisions = decide(prioritized, max_actions: max_actions)

        # Phase 4: ACT — dispatch through existing execution systems
        results = act(decisions)

        # Schedule next iteration
        ralph_loop.schedule_next_iteration!
        ralph_loop.increment_daily_iteration_count!

        {
          actions_taken: results.count { |r| r[:status] == :executed },
          observations_collected: observations.size,
          decisions: decisions.map { |d| { category: d[:category], action: d[:action_type], status: d[:status] } },
          cycle_completed_at: Time.current.iso8601
        }
      rescue StandardError => e
        Rails.logger.error("[DutyCycle] Error for agent #{agent.id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        ralph_loop.schedule_next_iteration!
        { actions_taken: 0, observations_collected: 0, decisions: [], error: e.message }
      end

      private

      # ===== OBSERVE =====
      # Collect signals from configured sensors.
      def observe(config)
        pipeline = ObservationPipelineService.new(account: account, agent: agent)
        pipeline.run(sensor_config: config&.dig("sensor_config"))
      end

      # ===== ORIENT =====
      # Rank observations by severity × relevance to goals × time sensitivity.
      # Filter by agent capability and merge duplicates.
      def orient(observations)
        goals = Ai::AgentGoal.for_agent(agent.id).actionable.by_priority.limit(5)

        scored = observations.map do |obs|
          {
            observation: obs,
            score: calculate_priority_score(obs, goals),
            category: categorize_observation(obs)
          }
        end

        # Deduplicate by observation_type + similar title (within same cycle)
        deduped = deduplicate(scored)

        # Sort by score descending
        deduped.sort_by { |s| -s[:score] }
      end

      # ===== DECIDE =====
      # Select actions based on oriented observations and agent context.
      # Uses structured decision-making rather than LLM to keep cycles fast and deterministic.
      def decide(prioritized, max_actions: MAX_ACTIONS_PER_CYCLE)
        config = ralph_loop.duty_cycle_config
        proactive_ratio = config["proactive_ratio"] || DEFAULT_PROACTIVE_RATIO

        # Check daily action limit
        daily_actions = daily_action_count
        remaining_daily = MAX_DAILY_ACTIONS - daily_actions
        return [] if remaining_daily <= 0

        max_actions = [max_actions, remaining_daily].min
        decisions = []

        # Separate by category
        urgent = prioritized.select { |p| p[:category] == "urgent_reaction" }
        approval_queue = prioritized.select { |p| p[:category] == "approval_queue" }
        goal_related = prioritized.select { |p| p[:category] == "active_goal_progress" }
        proactive = prioritized.select { |p| p[:category].in?(%w[proactive_improvement communication]) }

        # 1. Always handle urgent first
        urgent.first(max_actions).each do |item|
          decisions << build_decision(item, "react_to_alert")
        end

        # 2. Handle approval queue items
        remaining = max_actions - decisions.size
        approval_queue.first(remaining).each do |item|
          decisions << build_decision(item, "process_approval")
        end

        # 3. Progress active goals
        remaining = max_actions - decisions.size
        goal_slots = (remaining * (1 - proactive_ratio)).ceil
        goal_related.first(goal_slots).each do |item|
          decisions << build_decision(item, "progress_goal")
        end

        # 4. Proactive improvements (subject to ratio cap)
        remaining = max_actions - decisions.size
        proactive.first(remaining).each do |item|
          decisions << build_decision(item, "proactive_action")
        end

        decisions.first(max_actions)
      end

      # ===== ACT =====
      # Dispatch each decision through existing execution infrastructure.
      # All actions go through the ExecutionGateService for safety.
      def act(decisions)
        decisions.map do |decision|
          execute_decision(decision)
        end
      end

      # ----- Helpers -----

      def calculate_priority_score(observation, goals)
        severity_weight = case observation.severity
        when "critical" then 10
        when "warning" then 5
        when "info" then 1
        else 1
        end

        # Relevance to goals: boost if observation relates to an active goal
        goal_relevance = if observation.goal_id.present?
          3
        elsif goals.any? { |g| observation_relates_to_goal?(observation, g) }
          2
        else
          1
        end

        # Time sensitivity: boost observations close to expiry
        time_factor = if observation.expires_at.present?
          hours_remaining = ((observation.expires_at - Time.current) / 1.hour).to_f
          hours_remaining < 1 ? 3 : (hours_remaining < 4 ? 2 : 1)
        else
          1
        end

        requires_action_boost = observation.requires_action? ? 2 : 1

        severity_weight * goal_relevance * time_factor * requires_action_boost
      end

      def categorize_observation(observation)
        case observation.observation_type
        when "alert"
          observation.severity == "critical" ? "urgent_reaction" : "active_goal_progress"
        when "anomaly"
          "urgent_reaction"
        when "request"
          "approval_queue"
        when "degradation"
          "active_goal_progress"
        when "recommendation"
          "proactive_improvement"
        when "opportunity"
          "proactive_improvement"
        else
          "communication"
        end
      end

      def deduplicate(scored)
        seen = {}
        scored.reject do |s|
          obs = s[:observation]
          key = "#{obs.observation_type}:#{obs.sensor_type}"
          if seen[key]
            true
          else
            seen[key] = true
            false
          end
        end
      end

      def build_decision(item, action_type)
        {
          category: item[:category],
          action_type: action_type,
          observation: item[:observation],
          score: item[:score],
          status: :pending
        }
      end

      def execute_decision(decision)
        observation = decision[:observation]
        action_type = decision[:action_type]

        # Run through execution gate
        gate = ExecutionGateService.new(account: account)
        gate_result = gate.check(agent: agent, action_type: map_action_for_gate(action_type))

        if gate_result[:decision] == :denied
          decision[:status] = :denied
          decision[:reason] = gate_result[:reason]
          return decision
        end

        if gate_result[:decision] == :requires_approval
          decision[:status] = :requires_approval
          decision[:reason] = gate_result[:reason]
          # Mark observation as processed — awaiting approval
          observation.update(processed: true)
          return decision
        end

        # Execute the action
        case action_type
        when "react_to_alert"
          handle_alert_reaction(observation)
        when "process_approval"
          handle_approval_processing(observation)
        when "progress_goal"
          handle_goal_progress(observation)
        when "proactive_action"
          handle_proactive_action(observation)
        end

        observation.update(processed: true)
        decision[:status] = :executed
        decision
      rescue StandardError => e
        Rails.logger.error("[DutyCycle] Action #{action_type} failed: #{e.message}")
        decision[:status] = :failed
        decision[:reason] = e.message
        decision
      end

      def map_action_for_gate(action_type)
        case action_type
        when "react_to_alert" then "execute_tool"
        when "process_approval" then "execute_tool"
        when "progress_goal" then "execute_tool"
        when "proactive_action" then "send_proactive_notification"
        else "execute_tool"
        end
      end

      def handle_alert_reaction(observation)
        Rails.logger.info("[DutyCycle] Agent #{agent.id} reacting to alert: #{observation.title}")
        # For now, log the reaction. Future phases will dispatch to the agent's LLM
        # for intelligent response generation.
        record_action("react_to_alert", observation)
      end

      def handle_approval_processing(observation)
        Rails.logger.info("[DutyCycle] Agent #{agent.id} processing approval request: #{observation.title}")
        record_action("process_approval", observation)
      end

      def handle_goal_progress(observation)
        Rails.logger.info("[DutyCycle] Agent #{agent.id} progressing goal from observation: #{observation.title}")
        # Link observation to the most relevant active goal
        if observation.goal_id.nil?
          goals = Ai::AgentGoal.for_agent(agent.id).actionable.by_priority
          relevant = goals.find { |g| observation_relates_to_goal?(observation, g) }
          observation.update(goal_id: relevant.id) if relevant
        end
        record_action("progress_goal", observation)
      end

      def handle_proactive_action(observation)
        Rails.logger.info("[DutyCycle] Agent #{agent.id} proactive action: #{observation.title}")
        record_action("proactive_action", observation)
      end

      def record_action(action_type, observation)
        # Record in agent's execution history via metadata
        Ai::AgentExecution.create!(
          account_id: account.id,
          ai_agent_id: agent.id,
          execution_type: "duty_cycle",
          status: "completed",
          input_data: {
            action_type: action_type,
            observation_id: observation.id,
            observation_title: observation.title,
            duty_cycle_loop_id: ralph_loop.id
          },
          output_data: { result: "processed" },
          started_at: Time.current,
          completed_at: Time.current
        )
      rescue StandardError => e
        Rails.logger.warn("[DutyCycle] Failed to record action: #{e.message}")
      end

      def observation_relates_to_goal?(observation, goal)
        # Simple keyword matching — future: semantic similarity
        return false unless observation.title.present? && goal.title.present?

        obs_words = observation.title.downcase.split
        goal_words = goal.title.downcase.split
        (obs_words & goal_words).size >= 2
      end

      def daily_action_count
        Ai::AgentExecution
          .where(ai_agent_id: agent.id, execution_type: "duty_cycle")
          .where("created_at >= ?", Time.current.beginning_of_day)
          .count
      end
    end
  end
end
