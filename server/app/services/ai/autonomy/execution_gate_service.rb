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
      # @param user [User, nil] optional user context for intervention policy resolution
      # @return [Hash] { decision: :proceed/:requires_approval/:denied, reason: String|nil, approval_request_id: nil }
      def check(agent:, action_type: "execute", user: nil)
        checks = %i[
          check_account_suspension
          check_capability
          check_intervention_policy
          check_budget
          check_conformance
          check_behavioral_anomaly
          check_trust_freshness
        ]

        @current_agent = agent
        @current_action_type = action_type
        @current_user = user
        @capability_result = nil

        checks.each do |check_method|
          result = send(check_method, agent, action_type)
          return result if result
        end

        { decision: :proceed, reason: nil }
      end

      private

      # 0. Account AI suspension — is all AI activity halted?
      def check_account_suspension(_agent, _action_type)
        if @account.ai_suspended?
          { decision: :denied, reason: "AI activity suspended by administrator (since #{@account.ai_suspended_at&.iso8601})" }
        end
      end

      # 1. Capability matrix — does the agent's trust tier allow this action?
      def check_capability(agent, action_type)
        decision = Ai::Autonomy::CapabilityMatrixService
          .new(account: @account)
          .check(agent: agent, action_type: action_type)

        case decision
        when :denied
          { decision: :denied, reason: "Capability matrix denies '#{action_type}' for agent trust tier" }
        when :requires_approval
          # Store for intervention policy check — policy may override to :proceed
          @capability_result = :requires_approval
          nil
        end
      end

      # 1.5. Intervention policy — can auto-approve override requires_approval?
      # When capability matrix says requires_approval, the intervention policy
      # may promote to :proceed if auto_approve conditions are met.
      def check_intervention_policy(agent, action_type)
        # Only relevant when capability returned requires_approval
        if @capability_result == :requires_approval
          policy_service = ::Ai::InterventionPolicyService.new(account: @account)

          if policy_service.auto_approve?(action_category: action_type, agent: agent, user: @current_user)
            # Policy overrides — allow the action
            @capability_result = nil
            return nil
          end

          # No override — enforce the original requires_approval
          @capability_result = nil
          return {
            decision: :requires_approval,
            reason: "Capability matrix requires approval for '#{action_type}'",
            approval_request_id: nil
          }
        end

        # Check if policy explicitly blocks this action category
        policy_service = ::Ai::InterventionPolicyService.new(account: @account)
        if policy_service.blocked?(action_category: action_type, agent: agent, user: @current_user)
          return { decision: :denied, reason: "Intervention policy blocks '#{action_type}'" }
        end

        nil
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
