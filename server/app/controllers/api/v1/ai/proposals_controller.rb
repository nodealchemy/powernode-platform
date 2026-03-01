# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ProposalsController < ApplicationController
        before_action :validate_view_permissions
        before_action :validate_review_permissions, only: %i[approve reject batch_review]
        before_action :set_proposal, only: %i[show approve reject withdraw]

        # GET /api/v1/ai/proposals
        def index
          proposals = current_user.account.ai_agent_proposals
            .includes(:agent, :target_user, :reviewed_by)

          proposals = proposals.where(status: params[:status]) if params[:status].present?
          proposals = proposals.where(proposal_type: params[:type]) if params[:type].present?
          proposals = proposals.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?

          proposals = proposals.by_priority.order(created_at: :desc)
            .limit(params.fetch(:limit, 50).to_i)

          render_success(
            proposals: proposals.map { |p| serialize_proposal(p) },
            total_count: proposals.size
          )
        end

        # GET /api/v1/ai/proposals/:id
        def show
          render_success(serialize_proposal(@proposal))
        end

        # POST /api/v1/ai/proposals/:id/approve
        def approve
          @proposal.approve!(current_user)
          render_success(serialize_proposal(@proposal))
        end

        # POST /api/v1/ai/proposals/:id/reject
        def reject
          @proposal.reject!(current_user)
          render_success(serialize_proposal(@proposal))
        end

        # PUT /api/v1/ai/proposals/:id/withdraw
        def withdraw
          @proposal.withdraw!
          render_success(serialize_proposal(@proposal))
        end

        # POST /api/v1/ai/proposals/batch_review
        def batch_review
          service = ::Ai::ProposalService.new(account: current_user.account)
          results = service.batch_review(
            proposal_ids: params.require(:proposal_ids),
            action: params.require(:action),
            reviewer: current_user
          )

          render_success(results: results)
        end

        private

        def set_proposal
          @proposal = current_user.account.ai_agent_proposals.find(params[:id])
        end

        def validate_view_permissions
          require_permission("ai.proposals.view")
        end

        def validate_review_permissions
          require_permission("ai.proposals.review")
        end

        def serialize_proposal(proposal)
          {
            id: proposal.id,
            proposal_type: proposal.proposal_type,
            title: proposal.title,
            description: proposal.description,
            rationale: proposal.rationale,
            status: proposal.status,
            priority: proposal.priority,
            impact_assessment: proposal.impact_assessment,
            proposed_changes: proposal.proposed_changes,
            review_deadline: proposal.review_deadline&.iso8601,
            reviewed_at: proposal.reviewed_at&.iso8601,
            overdue: proposal.overdue?,
            agent: proposal.agent ? { id: proposal.agent.id, name: proposal.agent.name } : nil,
            target_user: proposal.target_user ? { id: proposal.target_user.id, email: proposal.target_user.email } : nil,
            reviewed_by: proposal.reviewed_by ? { id: proposal.reviewed_by.id, email: proposal.reviewed_by.email } : nil,
            created_at: proposal.created_at.iso8601,
            updated_at: proposal.updated_at.iso8601
          }
        end
      end
    end
  end
end
