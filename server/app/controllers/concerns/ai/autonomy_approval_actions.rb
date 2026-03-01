# frozen_string_literal: true

module Ai
  module AutonomyApprovalActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/approvals
    def approval_queue
      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)
      requests = service.pending_approvals

      render_success(data: requests.map { |r| serialize_approval_request(r) })
    end

    # POST /api/v1/ai/autonomy/approvals/:id/approve
    def approve_action
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)

      if service.approve(request: request, approver: current_user, comments: params[:comments])
        render_success(data: serialize_approval_request(request.reload))
      else
        render_error("Cannot approve this request", status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Approval request")
    end

    # POST /api/v1/ai/autonomy/approvals/:id/reject
    def reject_action
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)

      if service.reject(request: request, approver: current_user, comments: params[:comments])
        render_success(data: serialize_approval_request(request.reload))
      else
        render_error("Cannot reject this request", status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Approval request")
    end

    private

    def require_approval_permission
      return if current_worker

      require_permission("ai.autonomy.approve")
    end

    def serialize_approval_request(request)
      {
        id: request.id,
        request_id: request.request_id,
        agent_id: request.request_data&.dig("agent_id"),
        agent_name: request.request_data&.dig("agent_name"),
        action_type: request.request_data&.dig("action_type"),
        status: request.status,
        description: request.description,
        request_data: request.request_data,
        requested_by_id: request.requested_by_id,
        created_at: request.created_at,
        expires_at: request.expires_at,
        completed_at: request.completed_at
      }
    end
  end
end
