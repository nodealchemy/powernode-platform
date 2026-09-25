# frozen_string_literal: true

module Api
  module V1
    module Ai
      class InterventionPoliciesController < ApplicationController
        include ::HumanSession

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
          return refuse_unknown_agent if unknown_agent?(policy)
          return refuse_mark_write unless mark_write_permitted?(before: nil, after: policy.conditions)

          if policy.save
            render_success(serialize_policy(policy), status: :created)
          else
            render_error(policy.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH /api/v1/ai/intervention_policies/:id
        def update
          @policy.assign_attributes(policy_params)
          return refuse_unknown_agent if unknown_agent?(@policy)
          unless mark_write_permitted?(before: @policy.attribute_in_database(:conditions), after: @policy.conditions)
            return refuse_mark_write
          end

          if @policy.save
            render_success(serialize_policy(@policy))
          else
            render_error(@policy.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/intervention_policies/:id
        def destroy
          return refuse_mark_write unless mark_write_permitted?(before: @policy.conditions, after: nil)

          @policy.destroy!
          render_success(message: "Intervention policy deleted")
        end

        # GET /api/v1/ai/intervention_policies/grouped
        # Every account row, grouped by registered policy domain, for the panel.
        def grouped
          render_success(data: ::Ai::InterventionPolicies::GroupedView.new(account: current_user.account).as_json)
        end

        # PATCH /api/v1/ai/intervention_policies/bulk
        # body: { updates: [{ action_category, policy, scope?, agent_id?, ... }] }
        def bulk
          updates = Array(params[:updates])
          return render_error("updates array required", status: :bad_request) if updates.empty?

          result = ::Ai::InterventionPolicies::BulkUpdate
            .new(account: current_user.account, own_human_session: own_human_session?)
            .call(updates)

          if result.errors.any?
            render_error("Some updates failed", status: :unprocessable_content,
                                                details: { errors: result.errors, changed: result.changed })
          else
            render_success(data: { changed: result.changed, message: "#{result.changed} policies updated" })
          end
        end

        # POST /api/v1/ai/intervention_policies/resolve
        # Test policy resolution for a given context
        def resolve
          service = ::Ai::InterventionPolicyService.new(account: current_user.account)

          agent = params[:agent_id].present? ? ::Ai::Agent.for_account(current_user.account.id).find_by(id: params[:agent_id]) : nil
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

        # IMP-03134d9452d2: these rows decide which requests only a person may decide in
        # their own session (Ai::Approvals::HumanSessionPolicy#account_mark). A write that
        # could lift that mark needs that person's own session; the tool doors that write
        # the same rows are human-only for the same reason.
        def mark_write_permitted?(before:, after:)
          own_human_session? || !::Ai::Approvals::HumanSessionPolicy.mark_lifting_write?(before: before, after: after)
        end

        # The belongs_to carries no account check, so an ai_agent_id is admitted
        # only when it resolves to this account's agent or a global canonical one
        # (the same lookup #resolve uses); a foreign or nonexistent id is refused.
        def unknown_agent?(policy)
          policy.ai_agent_id.present? && policy.ai_agent_id_changed? &&
            !::Ai::Agent.for_account(current_user.account.id).exists?(id: policy.ai_agent_id)
        end

        def refuse_unknown_agent
          render_error("unknown agent", status: :unprocessable_content)
        end

        def refuse_mark_write
          render_error(::Ai::Approvals::HumanSessionPolicy::MARK_WRITE_REFUSAL, status: :forbidden)
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
            # Lexicographic, most-significant element first — see
            # Ai::InterventionPolicy#specificity_key. Was a single additive
            # `specificity_score`, whose arithmetic let `priority` outrank the
            # scope hierarchy (IMP-6430e3a8c4a1). No frontend consumer today.
            specificity_key: policy.specificity_key,
            created_at: policy.created_at.iso8601,
            updated_at: policy.updated_at.iso8601
          }
        end
      end
    end
  end
end
