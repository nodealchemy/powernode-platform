# frozen_string_literal: true

module Api
  module V1
    module Ai
      class InterventionPoliciesController < ApplicationController
        before_action :validate_permissions
        before_action :set_policy, only: %i[show update destroy]

        # GET /api/v1/ai/intervention_policies
        def index
          policies = current_user.account.ai_intervention_policies
            .includes(:user, :agent)

          policies = policies.active if params[:active] == "true"
          policies = policies.for_category(params[:action_category]) if params[:action_category].present?
          policies = policies.for_agent(params[:agent_id]) if params[:agent_id].present?

          policies = policies.by_specificity.limit(params.fetch(:limit, 50).to_i)

          render_success(
            policies: policies.map { |p| serialize_policy(p) },
            total_count: policies.size
          )
        end

        # GET /api/v1/ai/intervention_policies/:id
        def show
          render_success(serialize_policy(@policy))
        end

        # POST /api/v1/ai/intervention_policies
        def create
          policy = current_user.account.ai_intervention_policies.build(policy_params)

          if policy.save
            render_success(serialize_policy(policy), status: :created)
          else
            render_error(policy.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH /api/v1/ai/intervention_policies/:id
        def update
          if @policy.update(policy_params)
            render_success(serialize_policy(@policy))
          else
            render_error(@policy.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/ai/intervention_policies/:id
        def destroy
          @policy.destroy!
          render_success(message: "Intervention policy deleted")
        end

        # POST /api/v1/ai/intervention_policies/resolve
        # Test policy resolution for a given context
        def resolve
          service = ::Ai::InterventionPolicyService.new(account: current_user.account)

          agent = params[:agent_id].present? ? current_user.account.ai_agents.find_by(id: params[:agent_id]) : nil
          user = params[:user_id].present? ? current_user.account.users.find_by(id: params[:user_id]) : nil

          result = service.resolve(
            action_category: params.require(:action_category),
            agent: agent,
            user: user,
            severity: params[:severity]
          )

          render_success(result)
        end

        private

        def set_policy
          @policy = current_user.account.ai_intervention_policies.find(params[:id])
        end

        def policy_params
          params.permit(
            :scope, :action_category, :policy, :priority,
            :user_id, :ai_agent_id, :is_active,
            conditions: {},
            preferred_channels: []
          )
        end

        def validate_permissions
          require_permission("ai.intervention_policies.manage")
        end

        def serialize_policy(policy)
          {
            id: policy.id,
            scope: policy.scope,
            action_category: policy.action_category,
            policy: policy.policy,
            priority: policy.priority,
            is_active: policy.is_active,
            conditions: policy.conditions,
            preferred_channels: policy.preferred_channels,
            user: policy.user ? { id: policy.user.id, email: policy.user.email } : nil,
            agent: policy.agent ? { id: policy.agent.id, name: policy.agent.name } : nil,
            specificity_score: policy.specificity_score,
            created_at: policy.created_at.iso8601,
            updated_at: policy.updated_at.iso8601
          }
        end
      end
    end
  end
end
