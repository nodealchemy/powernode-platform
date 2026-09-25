# frozen_string_literal: true

module Ai
  module AutonomyDelegationActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/delegation_policies
    def delegation_policies
      service = ::Ai::Autonomy::DelegationAuthorityService.new(account: current_account)
      policies = service.list

      render_success(data: policies.map { |p| serialize_delegation_policy(p) })
    end

    # POST /api/v1/ai/autonomy/delegation_policies
    def create_delegation_policy
      agent = ::Ai::Agent.for_account(current_account.id).find(params[:agent_id])
      policy = ::Ai::DelegationPolicy.create!(
        account: current_account,
        agent: agent,
        max_depth: params[:max_depth] || 3,
        allowed_delegate_types: params[:allowed_delegate_types] || [],
        delegatable_actions: params[:delegatable_actions] || [],
        budget_delegation_pct: params[:budget_delegation_pct] || 0.5,
        inheritance_policy: params[:inheritance_policy] || "conservative"
      )

      render_success(data: serialize_delegation_policy(policy), status: :created)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_content)
    end

    private

    def serialize_delegation_policy(policy)
      {
        id: policy.id,
        agent_id: policy.agent_id,
        agent_name: policy.agent&.name,
        # A canonical (account-less) row is seed-managed and read-only here.
        canonical: policy.global?,
        max_depth: policy.max_depth,
        allowed_delegate_types: policy.allowed_delegate_types,
        delegatable_actions: policy.delegatable_actions,
        budget_delegation_pct: policy.budget_delegation_pct,
        inheritance_policy: policy.inheritance_policy,
        created_at: policy.created_at
      }
    end
  end
end
