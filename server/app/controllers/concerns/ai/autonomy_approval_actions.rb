# frozen_string_literal: true

module Ai
  module AutonomyApprovalActions
    extend ActiveSupport::Concern
    # IMP-550e44e24220 — the shared approval-payload core. Api::V1::Ai::
    # GovernanceController used to include it too, so neither read surface
    # could drift from the other; that controller's approval actions were
    # deleted in fc-12, so this is now its sole includer.
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
      card_refusal = change_card_refusal(request)
      return render_error(card_refusal, status: :unprocessable_content, code: "change_card_not_shown") if card_refusal
      digest_code, digest_refusal = change_card_digest_refusal(request)
      return render_error(digest_refusal, status: :unprocessable_content, code: digest_code) if digest_refusal

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

    # #human_session_refusal is HumanSession's. This is now the sole REST
    # decision door — the governance door's equivalent was deleted in fc-12.

    # APPROVING a request that carries a change card (the exact tool, setting and
    # values it asks for) is done from a surface that shows that card, and says
    # so with `change_card_shown` (the approvals queue sends it from the expanded
    # card). Any other surface is refused, pointed at the queue. Rejecting asks
    # nothing: it changes nothing. This is an attestation by the client, a guard
    # against deciding blind by accident or from a surface that cannot show the
    # card; the decider is still a person in their own session either way.
    def change_card_refusal(approval)
      return nil if ::ActiveModel::Type::Boolean.new.cast(params[:change_card_shown]) == true
      return nil unless decider_change_card(approval)

      "This request changes a setting, so approve it from the approvals queue " \
        "(/app/ai/control/approvals/queue), where the exact change is shown."
    end

    # The attestation above says a card was shown; the DIGEST says WHICH card
    # (IMP-1765f6f09458): the key, the new value and the current value at
    # render, as Ai::Approvals::ChangeCard rendered them. Recomputed here for
    # the decider's own session, now, and compared constant-time; a mismatch
    # means the setting changed (or was unset) since the person viewed it, and
    # the decision is refused rather than taken blind. Required wherever the
    # attestation is — every card-bearing request, a person's own park included:
    # the only surface that can truthfully attest the card was shown is one that
    # rendered it, and the rendered card carries the digest. A session not shown
    # the current value gets no digest and cannot complete the decision from
    # here; who may decide is otherwise unchanged. Rejecting asks nothing.
    # [code, message] or nil.
    def change_card_digest_refusal(approval)
      card = decider_change_card(approval)
      return nil unless card

      claimed = params[:change_card_digest]
      if claimed.blank?
        return [ "change_card_digest_missing",
                 "This request changes a setting, so approve it from the approvals queue " \
                 "(/app/ai/control/approvals/queue), which sends the digest of the card it shows." ]
      end
      unless card.key?(:digest)
        return [ "change_card_not_readable",
                 "Your session is not shown this setting's current value, so it cannot confirm the change " \
                 "as shown; a session that can read the setting decides it." ]
      end
      return nil if ::Ai::Approvals::ChangeCard.digest_matches?(card, claimed)

      [ "change_card_stale", "The request changed since you viewed it: the setting's current value is no " \
                             "longer what the card showed. Review the card again before deciding." ]
    end

    # One render per decision: the attestation, the digest and the response
    # all read the same card.
    def decider_change_card(approval)
      @decider_change_cards ||= {}
      return @decider_change_cards[approval.id] if @decider_change_cards.key?(approval.id)

      @decider_change_cards[approval.id] = ::Ai::Approvals::ChangeCard.for(approval, viewer: change_card_viewer)
    end

    # The change card's viewer answers has_permission? for THIS session
    # (Authentication#has_permission?, delegation-aware), not for current_user's
    # own roles (IMP-08ebabb04b42). nil without a user (a worker): no values.
    def change_card_viewer
      return nil unless current_user

      @change_card_viewer ||= ::Ai::Approvals::SessionViewer.new(user: current_user,
                                                                 permission_check: method(:has_permission?))
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
    # Ai::ApprovalRequestSerialization#approval_request_core, whose only
    # consumer this now is (the governance door's equivalent surface was
    # deleted in fc-12). Only this surface's own additions are listed here:
    # the agent_*/action_* denormalisations lifted out of request_data for the
    # approvals UI, the requester, and the step count (this surface reports
    # total_steps in the list payload and only adds step_statuses on detail).
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
        current_step_can_approve: current_user.present? && request.can_approve?(current_user),
        # The exact change a parked tool call asks for, from the redacted
        # request_data (nil when the tool offers none).
        change_card: ::Ai::Approvals::ChangeCard.for(request, viewer: change_card_viewer)
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
        preview: op.preview,
        # Written by the :fail event as "Class: message", so it can quote
        # those same params (IMP-3d275689ca7c).
        error_message: ::Ai::SensitiveParams.filter_text(op.error_message)
      }
    end
  end
end
