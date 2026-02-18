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

    # GET /api/v1/ai/autonomy/delegation_policies/:agent_id
    def agent_delegation_policy
      agent = current_account.ai_agents.find(params[:agent_id])
      policy = ::Ai::DelegationPolicy.find_by(agent_id: agent.id, account_id: current_account.id)

      if policy
        render_success(data: serialize_delegation_policy(policy))
      else
        render_success(data: nil)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    # POST /api/v1/ai/autonomy/delegation_policies
    def create_delegation_policy
      agent = current_account.ai_agents.find(params[:agent_id])
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
      render_error(e.message, status: :unprocessable_entity)
    end

    # PUT /api/v1/ai/autonomy/delegation_policies/:id
    def update_delegation_policy
      policy = ::Ai::DelegationPolicy.where(account_id: current_account.id).find(params[:id])
      policy.update!(delegation_policy_params)

      render_success(data: serialize_delegation_policy(policy))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Delegation policy")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_entity)
    end

    # DELETE /api/v1/ai/autonomy/delegation_policies/:id
    def destroy_delegation_policy
      policy = ::Ai::DelegationPolicy.where(account_id: current_account.id).find(params[:id])
      policy.destroy!

      render_success(data: { deleted: true })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Delegation policy")
    end

    private

    def delegation_policy_params
      params.permit(:max_depth, :budget_delegation_pct, :inheritance_policy,
                    allowed_delegate_types: [], delegatable_actions: [])
    end

    def serialize_delegation_policy(policy)
      {
        id: policy.id,
        agent_id: policy.agent_id,
        agent_name: policy.agent&.name,
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
