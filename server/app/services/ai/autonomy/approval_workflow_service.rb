# frozen_string_literal: true

module Ai
  module Autonomy
    # Wraps the multi-step approval chain workflow (Ai::ApprovalChain /
    # Ai::ApprovalRequest). Approval chains are a governance capability: a
    # single-operator core-mode deployment (no governance-providing extension) has
    # no approver-vs-actor separation, so each public method short-circuits when
    # governance is absent:
    #   - mutating methods return nil (or false where the caller expects Boolean)
    #   - listing methods return an empty array
    # The AutonomyGate's require_approval policy auto-proceeds via its own core-mode
    # branch (see ai/autonomy_gate.rb#require_approval_or_proceed), so nothing is lost.
    class ApprovalWorkflowService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Whether a governance-providing extension is loaded. Single source of truth
      # for the core-mode short-circuit (approval chains are a governance capability).
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

      # List pending approval requests
      # @return [ActiveRecord::Relation, Array<nil>] empty array in core mode
      def pending_approvals
        return [] unless self.class.governance_enabled?

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
      # @return [Boolean] false in core mode (no chain to approve against)
      def approve(request:, approver:, comments: nil)
        return false unless self.class.governance_enabled?
        return false unless request.account_id == account.id
        return false unless request.pending?
        return false unless request.can_approve?(approver)

        request.record_decision!(approver: approver, decision: "approved", comments: comments)
        true
      end

      # Reject a pending request. Rejection at any step terminates the chain.
      # @param request [Ai::ApprovalRequest] The request to reject
      # @param approver [User] The user rejecting
      # @param comments [String] Optional comments
      # @return [Boolean] false in core mode
      def reject(request:, approver:, comments: nil)
        return false unless self.class.governance_enabled?
        return false unless request.account_id == account.id
        return false unless request.pending?
        return false unless request.can_approve?(approver)

        request.record_decision!(approver: approver, decision: "rejected", comments: comments)
        true
      end

      # Expire overdue requests. Honours each chain's timeout_action
      # (approve/reject/escalate/expire) via check_expiration! — which also
      # cascades on_approval_decision to the source (e.g. expiring a CampaignLand
      # approval rejects the land) — instead of a bare status flip.
      # No-op in core mode (no requests to expire). Returns the count processed.
      def expire_overdue!
        return 0 unless self.class.governance_enabled?

        count = 0
        Ai::ApprovalRequest
          .where(account_id: account.id)
          .pending
          .where("expires_at <= ?", Time.current)
          .find_each do |request|
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
