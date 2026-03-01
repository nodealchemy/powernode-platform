# frozen_string_literal: true

module Ai
  module Autonomy
    class DelegationAuthorityService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Validate whether a delegator can delegate a task to a delegate agent
      # @param delegator [Ai::Agent] The agent delegating
      # @param delegate [Ai::Agent] The agent receiving the delegation
      # @param task [Hash] Task details including :action_type, :budget_cents
      # @return [Hash] { allowed: Boolean, reason: String|nil }
      def validate_delegation(delegator:, delegate:, task: {})
        policy = Ai::DelegationPolicy.find_by(agent_id: delegator.id)
        return { allowed: true, reason: nil } unless policy

        # Check depth
        depth = calculate_delegation_depth(delegator)
        if depth >= policy.max_depth
          return { allowed: false, reason: "Maximum delegation depth (#{policy.max_depth}) exceeded" }
        end

        # Check delegate type
        unless policy.allows_delegate_type?(delegate.agent_type)
          return { allowed: false, reason: "Delegate type '#{delegate.agent_type}' not in allowed types" }
        end

        # Check action type
        action_type = task[:action_type]
        if action_type.present? && !policy.allows_action?(action_type)
          return { allowed: false, reason: "Action '#{action_type}' not delegatable" }
        end

        # Check budget delegation
        budget_cents = task[:budget_cents].to_i
        if budget_cents.positive?
          delegator_budget = Ai::AgentBudget.where(agent_id: delegator.id).active.first
          if delegator_budget
            max_delegatable = (delegator_budget.remaining_cents * policy.budget_delegation_pct).to_i
            if budget_cents > max_delegatable
              return { allowed: false, reason: "Budget #{budget_cents} exceeds max delegatable #{max_delegatable} cents" }
            end
          end
        end

        { allowed: true, reason: nil }
      end

      # Get effective capabilities for an agent (own capabilities filtered by delegation constraints)
      # @param agent [Ai::Agent] The agent
      # @return [Hash] { capabilities: Hash, delegation_policy: DelegationPolicy|nil }
      def effective_capabilities(agent:)
        capability_service = CapabilityMatrixService.new(account: account)
        caps = capability_service.agent_capabilities(agent: agent)
        policy = Ai::DelegationPolicy.find_by(agent_id: agent.id)

        {
          capabilities: caps[:capabilities],
          tier: caps[:tier],
          delegation_policy: policy ? serialize_policy(policy) : nil
        }
      end

      # List all delegation policies
      def list
        Ai::DelegationPolicy.where(account_id: account.id).includes(:agent)
      end

      private

      def calculate_delegation_depth(agent)
        depth = 0
        current_id = agent.id
        visited = Set.new

        loop do
          break if visited.include?(current_id)

          visited.add(current_id)
          lineage = Ai::AgentLineage.for_child(current_id).active.first
          break unless lineage

          depth += 1
          current_id = lineage.parent_agent_id
        end

        depth
      end

      def serialize_policy(policy)
        {
          id: policy.id,
          agent_id: policy.agent_id,
          max_depth: policy.max_depth,
          allowed_delegate_types: policy.allowed_delegate_types,
          delegatable_actions: policy.delegatable_actions,
          budget_delegation_pct: policy.budget_delegation_pct,
          inheritance_policy: policy.inheritance_policy
        }
      end
    end
  end
end
