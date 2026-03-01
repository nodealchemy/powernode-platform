# frozen_string_literal: true

module Api
  module V1
    module Ai
      class FeedbackController < ApplicationController
        before_action :validate_submit_permissions, only: :create
        before_action :validate_view_permissions, only: :index

        # GET /api/v1/ai/feedback
        def index
          feedbacks = current_user.account.ai_agent_feedbacks
            .includes(:user, :agent)

          feedbacks = feedbacks.for_agent(params[:agent_id]) if params[:agent_id].present?
          feedbacks = feedbacks.where(feedback_type: params[:type]) if params[:type].present?

          feedbacks = feedbacks.recent.limit(params.fetch(:limit, 50).to_i)

          render_success(
            feedbacks: feedbacks.map { |f| serialize_feedback(f) },
            total_count: feedbacks.size
          )
        end

        # POST /api/v1/ai/feedback
        def create
          agent = current_user.account.ai_agents.find(params.require(:agent_id))
          service = ::Ai::FeedbackLoopService.new(account: current_user.account)

          feedback = service.record_feedback(
            agent: agent,
            user: current_user,
            feedback_type: params.require(:feedback_type),
            rating: params.require(:rating).to_i,
            comment: params[:comment],
            context_type: params[:context_type],
            context_id: params[:context_id]
          )

          render_success(serialize_feedback(feedback), status: :created)
        end

        private

        def validate_submit_permissions
          require_permission("ai.feedback.submit")
        end

        def validate_view_permissions
          require_permission("ai.feedback.view")
        end

        def serialize_feedback(feedback)
          {
            id: feedback.id,
            feedback_type: feedback.feedback_type,
            rating: feedback.rating,
            comment: feedback.comment,
            applied_to_trust: feedback.applied_to_trust,
            context_type: feedback.context_type,
            context_id: feedback.context_id,
            agent: feedback.agent ? { id: feedback.agent.id, name: feedback.agent.name } : nil,
            user: feedback.user ? { id: feedback.user.id, email: feedback.user.email } : nil,
            created_at: feedback.created_at.iso8601
          }
        end
      end
    end
  end
end
