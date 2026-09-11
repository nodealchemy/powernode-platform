# frozen_string_literal: true

module Ai
  module AutonomyApprovalActions
    extend ActiveSupport::Concern
    # IMP-550e44e24220 — shared approval-payload core, also included by
    # Api::V1::Ai::GovernanceController so both read surfaces cannot drift.
    include ::Ai::ApprovalRequestSerialization
    include ::HumanSession

    # GET /api/v1/ai/autonomy/approvals
    def approval_queue
      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)
      requests = service.pending_approvals

      # One pattern resolution for the whole page instead of one per row —
      # every serialized request filters its request_data (IMP-77645b94151e).
      data = ::Ai::SensitiveParams.batch { requests.map { |r| serialize_approval_request(r) } }
      render_success(data: data)
    end

    # GET /api/v1/ai/autonomy/approvals/:id
    def show_approval
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      data = ::Ai::SensitiveParams.batch { serialize_approval_request(request, detailed: true) }
      render_success(data: data)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Approval request")
    end

    # POST /api/v1/ai/autonomy/approvals/:id/approve
    def approve_action
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      refusal = human_session_refusal(request, "approve")
      return render_error(refusal, status: :forbidden) if refusal

      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)

      if service.approve(request: request, approver: current_user, comments: params[:comments],
                         origin: human_decision_origin)
        payload = ::Ai::SensitiveParams.batch { serialize_approval_request(request.reload, detailed: true) }
        render_success(data: with_revealed_result(request, payload))
      else
        # L9: a refusal the decider can act on is named; any other stays generic.
        return render_error(request.decision_refusal, status: :forbidden) if request.decision_refusal

        render_error("Cannot approve this request", status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Approval request")
    end

    # POST /api/v1/ai/autonomy/approvals/:id/reject
    def reject_action
      request = ::Ai::ApprovalRequest.where(account_id: current_account.id).find(params[:id])
      refusal = human_session_refusal(request, "reject")
      return render_error(refusal, status: :forbidden) if refusal

      service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: current_account)

      if service.reject(request: request, approver: current_user, comments: params[:comments],
                        origin: human_decision_origin)
        render_success(
          data: ::Ai::SensitiveParams.batch { serialize_approval_request(request.reload, detailed: true) }
        )
      else
        render_error("Cannot reject this request", status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Approval request")
    end

    private

    # MCP identity plan R2 and D1: a request that needs a person's own session
    # (Ai::ApprovalRequest#requires_human_session?), and a tool-door request
    # decided by the person who asked for it (guard a), are decided only from
    # that person's own session. An impersonation, account-switch or service
    # session is refused by name.
    def human_session_refusal(request, verb)
      return nil if own_human_session?

      if request.requires_human_session?
        return "Cannot #{verb} this request from this session: it needs a person deciding it in their own session, " \
               "not an impersonation, account-switch or service session."
      end
      return nil unless request.requester_excluded?(approver: current_user, origin: human_decision_origin)

      "Cannot #{verb} this request from this session: you asked for it through a tool, so you decide it only " \
        "in your own session, not an impersonation, account-switch or service session."
    end

    def require_approval_permission
      return if current_worker

      require_permission("ai.autonomy.approve")
    end

    # Reveal-once handoff (IMP-7b81ca22f661) — the ONE surface an executor that
    # minted secret material can be seen from when the operation was deferred.
    # Everything else about this row is redacted (request_data and the
    # operation's params both go through Ai::SensitiveParams, and :result is
    # filtered at rest), which is exactly why the mint would otherwise be
    # revealed zero times rather than once.
    #
    # Deliberately merged only into the approve response, and only when the
    # decision actually ran an executor: the slot is emptied by this read, so
    # every later read of the same row — including #show_approval — sees
    # nothing. Nothing is persisted, so nothing can be re-fetched.
    def with_revealed_result(request, payload)
      revealed = request.take_revealed_result!
      return payload if revealed.blank?

      payload.merge(revealed_result: revealed)
    end

    # IMP-550e44e24220 — the shared fields come from
    # Ai::ApprovalRequestSerialization#approval_request_core, which is the
    # single definition both approval read surfaces build on. Only this
    # surface's own additions are listed here: the agent_*/action_*
    # denormalisations lifted out of request_data for the approvals UI, the
    # requester, and the step count (this surface reports total_steps in the
    # list payload and only adds step_statuses on detail).
    def serialize_approval_request(request, detailed: false)
      base = approval_request_core(request).merge(
        agent_id: request.request_data&.dig("agent_id"),
        agent_name: request.request_data&.dig("agent_name"),
        # action_type is what the approvals UI titles a card with, but only
        # Ai::Approvals::Gateway writes that key. Ai::AutonomyGate and the
        # fleet autonomy service write action_category, so without this
        # fallback every gate-parked and fleet-signal card rendered a blank
        # title (IMP: blank approval cards, 2026-09-08).
        action_type: request.request_data&.dig("action_type") || request.request_data&.dig("action_category"),
        action_category: request.request_data&.dig("action_category"),
        requested_by_id: request.requested_by_id,
        total_steps: request.step_statuses&.size,
        # Per viewer, on the LIST as well as the detail (C3b2 review B1): the
        # client offers Approve/Reject only when this is true, and until it was
        # listed the quick row followed the permission alone, so a holder of
        # ai.autonomy.approve who is not on the current step drew a 422.
        current_step_can_approve: current_user.present? && request.can_approve?(current_user)
      )
      return base unless detailed

      base.merge(
        approval_chain: serialize_chain(request.approval_chain),
        step_statuses: request.step_statuses,
        decisions: request.decisions.order(:created_at).map { |d| serialize_decision(d) },
        deferred_operation: serialize_deferred_operation(request)
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
        comments: decision.comments, origin: decision.origin, created_at: decision.created_at
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
