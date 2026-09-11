# frozen_string_literal: true

module Ai
  module Autonomy
    # Wraps the multi-step approval chain workflow (Ai::ApprovalChain /
    # Ai::ApprovalRequest).
    #
    # Two sides, gated differently (IMP-27e2f8e59ce0):
    #   - CREATION (#request_approval) is a governance capability: it short-
    #     circuits to nil when no governance-providing extension is loaded, and
    #     Ai::Approvals::Gateway proceeds instead of parking.
    #   - DECISION (#pending_approvals, #approve, #reject, #expire_overdue!) works
    #     on any request that EXISTS, capability or not. Ai::ApprovalChain and
    #     Ai::ApprovalRequest are core models; Ai::AutonomyGate parks every
    #     require_approval action behind one on every deployment, and the
    #     governance decide endpoint (Ai::GovernanceService#process_approval_decision)
    #     already decides them with no capability check. Gating the decision on
    #     the capability produced the 2026-09-08 core-mode hub incident: the
    #     operator saw the card, POST .../approvals/:id/approve answered 422
    #     "Cannot approve this request", and the deferred operation was stranded
    #     until its timeout. A request nobody can decide is worse than no request.
    class ApprovalWorkflowService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Whether a governance-providing extension is loaded. Gates request CREATION
      # here and in Ai::Approvals::Gateway; it does NOT gate deciding a request
      # that already exists (see the class comment).
      def self.governance_enabled?
        Shared::FeatureGateService.capability_present?(:governance)
      end

      # Create an approval request for an autonomy action
      # @param agent [Ai::Agent] The agent requesting the action
      # @param action_type [String] The action type
      # @param description [String] Description of what's being requested
      # @param request_data [Hash] Additional context data
      # @param requested_by [User] The user who triggered the request (optional)
      # @return [Ai::ApprovalRequest, nil] nil in core mode
      def request_approval(agent:, action_type:, description:, request_data: {}, requested_by: nil)
        return nil unless self.class.governance_enabled?

        chain = find_or_create_chain(action_type)

        chain.create_request!(
          source_type: "Ai::Agent",
          source_id: agent.id,
          description: description,
          request_data: request_data.merge(
            agent_id: agent.id,
            agent_name: agent.name,
            action_type: action_type
          ),
          requested_by: requested_by
        )
      end

      # List pending approval requests — every request that exists, whichever
      # path created it (the gate creates them in core mode too).
      # @return [ActiveRecord::Relation]
      def pending_approvals
        Ai::ApprovalRequest
          .where(account_id: account.id)
          .pending
          .includes(:approval_chain)
          .order(created_at: :asc)
      end

      # Approve a pending request. Routes through record_decision! so the
      # underlying multi-step machinery (process_decision, advance_to_next_step!,
      # final-step approve!) runs — single-step chains terminate immediately,
      # multi-step chains advance to the next step.
      # @param request [Ai::ApprovalRequest] The request to approve
      # @param approver [User] The user approving
      # @param comments [String] Optional comments
      # @param origin [String, nil] the door the decision came through
      #   (Ai::ApprovalDecision ORIGINS). A requires_human_session request needs
      #   Ai::ApprovalDecision::REST_SESSION.
      # @param agent [Ai::Agent, nil] the agent a tool door carries. The
      #   principal that asked for a tool-door request does not decide it
      #   (Ai::ApprovalRequest#requester_excluded?).
      # @return [Boolean] false when the request is not this account's, not
      #   pending, or the approver does not match the current step
      def approve(request:, approver:, comments: nil, origin: nil, agent: nil)
        return false unless request.account_id == account.id
        return false unless request.pending?
        return false unless request.can_approve?(approver)

        # The decision's own answer, not a constant: it is false when a racing
        # decision by the same approver got there first (the unique index).
        request.record_decision!(approver: approver, decision: "approved", comments: comments,
                                 origin: origin, agent: agent) ? true : false
      end

      # Reject a pending request. Rejection at any step terminates the chain.
      # @param request [Ai::ApprovalRequest] The request to reject
      # @param approver [User] The user rejecting
      # @param comments [String] Optional comments
      # @return [Boolean] false when the request is not this account's, not
      #   pending, or the approver does not match the current step
      def reject(request:, approver:, comments: nil, origin: nil, agent: nil)
        return false unless request.account_id == account.id
        return false unless request.pending?
        return false unless request.can_approve?(approver)

        request.record_decision!(approver: approver, decision: "rejected", comments: comments,
                                 origin: origin, agent: agent) ? true : false
      end

      # Expire overdue requests. Honours each chain's timeout_action
      # (approve/reject/escalate/expire) via check_expiration! — which also
      # cascades on_approval_decision to the source (e.g. expiring a CampaignLand
      # approval rejects the land) — instead of a bare status flip.
      # Runs on every deployment: a request the gate parked in core mode must
      # still time out. Returns the count processed.
      #
      # Bounded per call: check_expiration! cascades each chain's timeout_action
      # (reject by default, but an operator can set a chain to "approve", which
      # EXECUTES the parked operation). Before this method ran in core mode a
      # deployment could accumulate an unbounded pending backlog; settling it in
      # one hourly tick would fire every cascade at once. The hourly sweep
      # (AiApprovalExpiryJob → internal autonomy#expire_overdue_approval_requests)
      # drains the rest on later ticks. Oldest first, so a request is never
      # starved by newer ones.
      EXPIRY_SWEEP_LIMIT = 100

      def expire_overdue!(limit: EXPIRY_SWEEP_LIMIT)
        count = 0
        Ai::ApprovalRequest
          .where(account_id: account.id)
          .pending
          .where("expires_at <= ?", Time.current)
          .order(:expires_at)
          .limit(limit)
          .each do |request|
            request.check_expiration!
            count += 1
          end
        count
      end

      private

      def find_or_create_chain(action_type)
        Ai::ApprovalChain.find_or_strengthen!(
          account: account, name: "autonomy_#{action_type}", step_name: "autonomy_approval",
          approvers: [ "*" ], required_approvals: 1,
          defaults: { trigger_type: "autonomy_action", status: "active", timeout_hours: 24 }
        )
      end
    end
  end
end
