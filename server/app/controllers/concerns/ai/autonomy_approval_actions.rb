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

    # GET /api/v1/ai/autonomy/approvals/:id
    def show_approval
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      render_success(data: serialize_approval_request(request, detailed: true))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Approval request")
    end

    # POST /api/v1/ai/autonomy/approvals/:id/approve
    def approve_action
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)

      if service.approve(request: request, approver: current_user, comments: params[:comments])
        render_success(data: serialize_approval_request(request.reload, detailed: true))
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
        render_success(data: serialize_approval_request(request.reload, detailed: true))
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

    def serialize_approval_request(request, detailed: false)
      base = {
        id: request.id,
        request_id: request.request_id,
        agent_id: request.request_data&.dig("agent_id"),
        agent_name: request.request_data&.dig("agent_name"),
        action_type: request.request_data&.dig("action_type"),
        action_category: request.request_data&.dig("action_category"),
        source_type: request.source_type,
        source_id: request.source_id,
        status: request.status,
        description: request.description,
        # Filtered again at the read, not just at Ai::AutonomyGate's write:
        # request_data has producers other than the gate (Ai::GovernanceService,
        # Ai::Approvals::Gateway, the mission orchestrator), and rows written
        # before the gate started redacting still hold plaintext — the read is
        # the only surface that covers those retroactively.
        request_data: ::Ai::SensitiveParams.filter(request.request_data),
        requested_by_id: request.requested_by_id,
        created_at: request.created_at,
        expires_at: request.expires_at,
        completed_at: request.completed_at,
        current_step: request.current_step,
        total_steps: request.step_statuses&.size
      }
      return base unless detailed

      base.merge(
        approval_chain: serialize_chain(request.approval_chain),
        step_statuses: request.step_statuses,
        decisions: request.decisions.order(:created_at).map { |d| serialize_decision(d) },
        deferred_operation: serialize_deferred_operation(request),
        current_step_can_approve: current_user.present? && request.can_approve?(current_user)
      )
    end

    def serialize_chain(chain)
      return nil unless chain
      {
        id: chain.id, name: chain.name, is_sequential: chain.is_sequential,
        timeout_hours: chain.timeout_hours, timeout_action: chain.timeout_action,
        steps: chain.steps
      }
    end

    def serialize_decision(decision)
      {
        id: decision.id, approver_id: decision.approver_id,
        step_number: decision.step_number, decision: decision.decision,
        comments: decision.comments, created_at: decision.created_at
      }
    end

    def serialize_deferred_operation(request)
      return nil unless request.source_type == "Ai::DeferredOperation"
      op = ::Ai::DeferredOperation.find_by(id: request.source_id)
      return nil unless op
      {
        id: op.id, action_category: op.action_category,
        executor_class: op.executor_class, status: op.status,
        # The operation's OWN params, a second copy that never passes through
        # request_data — a fix applied only at the gate's copy boundary would
        # leave this one serving plaintext.
        params: ::Ai::SensitiveParams.filter(op.params),
        preview: op.preview, error_message: op.error_message
      }
    end
  end
end
