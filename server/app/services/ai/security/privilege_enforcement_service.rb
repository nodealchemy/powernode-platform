# frozen_string_literal: true

module Ai
  module Security
    class PrivilegeEnforcementService
      # OWASP ASI05 - Least Privilege Enforcement
      # Evaluates agent privilege policies to allow/deny actions, tools, and communications.

      ESCALATION_WINDOW = 1.hour
      ESCALATION_THRESHOLD = 5

      class EnforcementError < StandardError; end

      def initialize(account:)
        @account = account
      end

      # Check whether an agent is allowed to perform a given action on a resource.
      # Returns { allowed: bool, reason: String|nil, policy_id: UUID|nil }
      def check_action!(agent:, action:, resource: nil)
        # Quarantine gate: block if agent is under active quarantine
        quarantine_denial = evaluate_quarantine_gate(agent)
        return quarantine_denial if quarantine_denial

        policies = policies_for_agent(agent: agent)

        policies.each do |policy|
          result = evaluate_policy_action(policy, action, resource)
          next if result[:allowed]

          log_enforcement(agent, action, "denied", policy: policy)
          return { allowed: false, reason: result[:reason], policy_id: policy.id }
        end

        log_enforcement(agent, action, "allowed")
        { allowed: true, reason: nil, policy_id: nil }
      rescue StandardError => e
        Rails.logger.error "[PrivilegeEnforcement] check_action! error: #{e.message}"
        { allowed: false, reason: "Privilege check error (fail-closed)", policy_id: nil }
      end

      # Check whether an agent is allowed to use a specific tool.
      # Returns { allowed: bool, reason: String|nil, policy_id: UUID|nil }
      def check_tool!(agent:, tool_name:, arguments: {})
        # Quarantine gate: block if agent is under active quarantine
        quarantine_denial = evaluate_quarantine_gate(agent)
        return quarantine_denial if quarantine_denial

        policies = policies_for_agent(agent: agent)

        policies.each do |policy|
          unless policy.tool_allowed?(tool_name)
            log_enforcement(agent, "tool:#{tool_name}", "denied", policy: policy)
            return { allowed: false, reason: "Tool '#{tool_name}' denied by policy '#{policy.policy_name}'", policy_id: policy.id }
          end
        end

        log_enforcement(agent, "tool:#{tool_name}", "allowed")
        { allowed: true, reason: nil, policy_id: nil }
      rescue StandardError => e
        Rails.logger.error "[PrivilegeEnforcement] check_tool! error: #{e.message}"
        { allowed: false, reason: "Tool check error (fail-closed)", policy_id: nil }
      end

      # Check whether inter-agent communication is permitted.
      # Returns { allowed: bool, reason: String|nil, policy_id: UUID|nil }
      def check_communication!(from_agent:, to_agent:, message_type: "default")
        # Quarantine gate: block if sender is under active quarantine
        quarantine_denial = evaluate_quarantine_gate(from_agent)
        return quarantine_denial if quarantine_denial

        from_policies = policies_for_agent(agent: from_agent)

        from_policies.each do |policy|
          unless policy.communication_allowed?(from_agent.id, to_agent.id)
            log_enforcement(from_agent, "communicate:#{to_agent.id}", "denied", policy: policy)
            return {
              allowed: false,
              reason: "Communication from #{from_agent.id} to #{to_agent.id} denied by policy '#{policy.policy_name}'",
              policy_id: policy.id
            }
          end
        end

        log_enforcement(from_agent, "communicate:#{to_agent.id}", "allowed")
        { allowed: true, reason: nil, policy_id: nil }
      rescue StandardError => e
        Rails.logger.error "[PrivilegeEnforcement] check_communication! error: #{e.message}"
        { allowed: false, reason: "Communication check error (fail-closed)", policy_id: nil }
      end

      # Detect privilege escalation patterns in an agent's recent action history.
      # Returns { escalation_score: Float, escalated: bool, recommended_action: String }
      def detect_escalation(agent:, action_history: [])
        recent_denials = Ai::SecurityAuditTrail
          .for_agent(agent.id)
          .by_outcome("denied")
          .recent(ESCALATION_WINDOW)
          .count

        recent_blocks = Ai::SecurityAuditTrail
          .for_agent(agent.id)
          .by_outcome("blocked")
          .recent(ESCALATION_WINDOW)
          .count

        # Compute escalation score based on denial/block frequency and action diversity
        denial_score = [recent_denials.to_f / ESCALATION_THRESHOLD, 1.0].min
        block_score = [recent_blocks.to_f / (ESCALATION_THRESHOLD / 2), 1.0].min

        # Check for diverse denied actions (agent trying many different things = possible escalation)
        diverse_actions = Ai::SecurityAuditTrail
          .for_agent(agent.id)
          .by_outcome("denied")
          .recent(ESCALATION_WINDOW)
          .distinct
          .count(:action)
        diversity_score = [diverse_actions.to_f / 5.0, 1.0].min

        escalation_score = (denial_score * 0.4 + block_score * 0.3 + diversity_score * 0.3).round(4)
        escalated = escalation_score >= 0.6

        recommended_action = if escalation_score >= 0.8
                               "quarantine"
                             elsif escalated
                               "restrict_capabilities"
                             elsif escalation_score >= 0.3
                               "increase_monitoring"
                             else
                               "none"
                             end

        if escalated
          Ai::SecurityAuditTrail.log!(
            action: "privilege_escalation_detected",
            outcome: "escalated",
            account: @account,
            agent_id: agent.id,
            asi_reference: "ASI05",
            csa_pillar: "behavior",
            risk_score: escalation_score,
            source_service: "PrivilegeEnforcementService",
            severity: escalation_score >= 0.8 ? "critical" : "warning",
            details: {
              denial_count: recent_denials,
              block_count: recent_blocks,
              diverse_actions: diverse_actions,
              recommended_action: recommended_action
            }
          )
        end

        { escalation_score: escalation_score, escalated: escalated, recommended_action: recommended_action }
      rescue StandardError => e
        Rails.logger.error "[PrivilegeEnforcement] detect_escalation error: #{e.message}"
        { escalation_score: 0.0, escalated: false, recommended_action: "error" }
      end

      # Enforce escalation detection: detect escalation, then quarantine if warranted.
      def enforce_escalation!(agent:)
        result = detect_escalation(agent: agent)
        return result unless result[:escalated]

        quarantine_service = Ai::Security::QuarantineService.new(account: @account)

        case result[:recommended_action]
        when "quarantine"
          quarantine_service.quarantine!(
            agent: agent,
            severity: "high",
            reason: "Privilege escalation detected (score: #{result[:escalation_score]})",
            source: "anomaly_detection"
          )
        when "restrict_capabilities"
          quarantine_service.quarantine!(
            agent: agent,
            severity: "medium",
            reason: "Privilege escalation pattern detected (score: #{result[:escalation_score]})",
            source: "anomaly_detection"
          )
        end

        result
      rescue StandardError => e
        Rails.logger.error "[PrivilegeEnforcement] enforce_escalation! error: #{e.message}"
        result || { escalation_score: 0.0, escalated: false, recommended_action: "error" }
      end

      # Load all applicable policies for an agent, sorted by priority.
      def policies_for_agent(agent:)
        trust_tier = trust_tier_for_agent(agent)
        Ai::AgentPrivilegePolicy.where(account: @account)
          .applicable_to(agent.id, trust_tier)
      end

      private

      def evaluate_quarantine_gate(agent)
        return nil unless Ai::QuarantineRecord.where(agent_id: agent.id, account: @account).active.exists?

        log_enforcement(agent, "quarantine_gate", "blocked")
        { allowed: false, reason: "Agent is under active quarantine", policy_id: nil }
      end

      def evaluate_policy_action(policy, action, resource)
        unless policy.action_allowed?(action)
          return { allowed: false, reason: "Action '#{action}' denied by policy '#{policy.policy_name}'" }
        end

        if resource.present? && !policy.resource_allowed?(resource)
          return { allowed: false, reason: "Resource '#{resource}' denied by policy '#{policy.policy_name}'" }
        end

        { allowed: true, reason: nil }
      end

      def trust_tier_for_agent(agent)
        return nil unless agent.respond_to?(:trust_score)

        agent.trust_score&.tier
      end

      def log_enforcement(agent, action, outcome, policy: nil)
        Ai::SecurityAuditTrail.log!(
          action: "privilege_check:#{action}",
          outcome: outcome,
          account: @account,
          agent_id: agent.id,
          asi_reference: "ASI05",
          csa_pillar: "behavior",
          source_service: "PrivilegeEnforcementService",
          severity: outcome == "denied" ? "warning" : "info",
          details: {
            policy_id: policy&.id,
            policy_name: policy&.policy_name
          }.compact
        )
      rescue StandardError => e
        Rails.logger.error "[PrivilegeEnforcement] log_enforcement failed: #{e.message}"
      end
    end
  end
end
