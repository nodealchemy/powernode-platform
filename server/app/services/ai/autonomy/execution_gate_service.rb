# frozen_string_literal: true

module Ai
  module Autonomy
    class ExecutionGateService
      TRUST_FRESHNESS_DAYS = 7

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Pre-execution governance gate — runs all checks in priority order.
      # Returns on the first blocking result or :proceed if all pass.
      #
      # @param agent [Ai::Agent]
      # @param action_type [String] e.g. "execute", "spawn_agent", "modify_system"
      # @return [Hash] { decision: :proceed/:requires_approval/:denied, reason: String|nil, approval_request_id: nil }
      def check(agent:, action_type: "execute")
        checks = %i[
          check_capability
          check_budget
          check_conformance
          check_behavioral_anomaly
          check_trust_freshness
        ]

        checks.each do |check_method|
          result = send(check_method, agent, action_type)
          return result if result
        end

        { decision: :proceed, reason: nil }
      end

      private

      # 1. Capability matrix — does the agent's trust tier allow this action?
      def check_capability(agent, action_type)
        decision = Ai::Autonomy::CapabilityMatrixService
          .new(account: @account)
          .check(agent: agent, action_type: action_type)

        case decision
        when :denied
          { decision: :denied, reason: "Capability matrix denies '#{action_type}' for agent trust tier" }
        when :requires_approval
          { decision: :requires_approval, reason: "Capability matrix requires approval for '#{action_type}'", approval_request_id: nil }
        end
      end

      # 2. Budget sufficiency — does the agent have remaining budget?
      def check_budget(agent, _action_type)
        budget = Ai::AgentBudget.where(agent_id: agent.id).active.first
        return nil unless budget

        if budget.remaining_cents <= 0
          { decision: :denied, reason: "Agent budget exhausted (#{budget.utilization_percentage}% utilized)" }
        end
      end

      # 3. Conformance engine — are temporal governance rules satisfied?
      def check_conformance(agent, _action_type)
        result = Ai::Autonomy::ConformanceEngineService
          .new(account: @account)
          .check_event(agent: agent, event_type: "action_executed")

        return nil if result[:conformant]

        high_violations = result[:violations].select { |v| v[:severity] == "high" }
        return nil if high_violations.empty?

        messages = high_violations.map { |v| v[:message] }
        { decision: :denied, reason: "Conformance violations: #{messages.join('; ')}" }
      end

      # 4. Behavioral fingerprint — is the agent behaving anomalously?
      def check_behavioral_anomaly(agent, _action_type)
        result = Ai::Autonomy::BehavioralFingerprintService
          .new(account: @account)
          .detect_anomaly(
            agent: agent,
            metric_name: "execution_frequency",
            value: recent_execution_count(agent)
          )

        return nil unless result[:anomaly]

        {
          decision: :requires_approval,
          reason: "Behavioral anomaly detected: execution frequency z-score #{result[:z_score]}",
          approval_request_id: nil
        }
      end

      # 5. Trust score freshness — has the agent been evaluated recently?
      def check_trust_freshness(agent, _action_type)
        trust_score = Ai::AgentTrustScore.find_by(agent_id: agent.id)

        if trust_score.nil?
          return {
            decision: :requires_approval,
            reason: "No trust score on record for agent",
            approval_request_id: nil
          }
        end

        if trust_score.last_evaluated_at.nil? || trust_score.last_evaluated_at < TRUST_FRESHNESS_DAYS.days.ago
          {
            decision: :requires_approval,
            reason: "Trust score stale (last evaluated #{trust_score.last_evaluated_at&.iso8601 || 'never'})",
            approval_request_id: nil
          }
        end
      end

      # Count agent executions in the last hour
      def recent_execution_count(agent)
        Ai::AgentExecution
          .where(ai_agent_id: agent.id)
          .where("created_at >= ?", 1.hour.ago)
          .count
      end
    end
  end
end
