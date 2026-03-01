# frozen_string_literal: true

module Api
  module V1
    module Ai
      class EscalationsController < ApplicationController
        before_action :validate_view_permissions
        before_action :validate_resolve_permissions, only: %i[acknowledge resolve]
        before_action :set_escalation, only: %i[show acknowledge resolve]

        # GET /api/v1/ai/escalations
        def index
          escalations = current_user.account.ai_agent_escalations
            .includes(:agent, :escalated_to_user)

          escalations = escalations.where(status: params[:status]) if params[:status].present?
          escalations = escalations.where(severity: params[:severity]) if params[:severity].present?
          escalations = escalations.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?

          escalations = escalations.by_severity.order(created_at: :desc)
            .limit(params.fetch(:limit, 50).to_i)

          render_success(
            escalations: escalations.map { |e| serialize_escalation(e) },
            total_count: escalations.size
          )
        end

        # GET /api/v1/ai/escalations/:id
        def show
          render_success(serialize_escalation(@escalation))
        end

        # POST /api/v1/ai/escalations/:id/acknowledge
        def acknowledge
          @escalation.acknowledge!(current_user)
          render_success(serialize_escalation(@escalation))
        end

        # POST /api/v1/ai/escalations/:id/resolve
        def resolve
          @escalation.resolve!
          render_success(serialize_escalation(@escalation))
        end

        private

        def set_escalation
          @escalation = current_user.account.ai_agent_escalations.find(params[:id])
        end

        def validate_view_permissions
          require_permission("ai.escalations.view")
        end

        def validate_resolve_permissions
          require_permission("ai.escalations.resolve")
        end

        def serialize_escalation(escalation)
          {
            id: escalation.id,
            escalation_type: escalation.escalation_type,
            severity: escalation.severity,
            status: escalation.status,
            title: escalation.title,
            context: escalation.context,
            escalation_chain: escalation.escalation_chain,
            current_level: escalation.current_level,
            timeout_hours: escalation.timeout_hours,
            next_escalation_at: escalation.next_escalation_at&.iso8601,
            acknowledged_at: escalation.acknowledged_at&.iso8601,
            resolved_at: escalation.resolved_at&.iso8601,
            agent: escalation.agent ? { id: escalation.agent.id, name: escalation.agent.name } : nil,
            escalated_to: escalation.escalated_to_user ? {
              id: escalation.escalated_to_user.id,
              email: escalation.escalated_to_user.email
            } : nil,
            created_at: escalation.created_at.iso8601,
            updated_at: escalation.updated_at.iso8601
          }
        end
      end
    end
  end
end
