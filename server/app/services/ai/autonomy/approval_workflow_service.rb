# frozen_string_literal: true

module Ai
  module Autonomy
    # Wraps the multi-step approval chain workflow. The chain + request
    # models (Ai::ApprovalChain, Ai::ApprovalRequest) live in the
    # business extension — in core mode (no business loaded) every
    # method here would raise NameError on first model reference.
    # Each public method short-circuits via .business_loaded? when the
    # extension isn't present:
    #   - mutating methods return nil (or false where the caller expects
    #     Boolean), matching the documented no-success outcome
    #   - listing methods return an empty array
    # Single-operator core-mode deployments don't have approver-vs-actor
    # separation, so there's no chain to drive; the AutonomyGate's
    # require_approval policy auto-proceeds via its own core-mode branch
    # (see ai/autonomy_gate.rb#require_approval_or_proceed).
    class ApprovalWorkflowService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Whether the business extension's approval models are loaded.
      # Single source of truth for the core-mode short-circuit.
      def self.business_loaded?
        defined?(::Ai::ApprovalChain) && defined?(::Ai::ApprovalRequest)
      end

      # Create an approval request for an autonomy action
      # @param agent [Ai::Agent] The agent requesting the action
      # @param action_type [String] The action type
      # @param description [String] Description of what's being requested
      # @param request_data [Hash] Additional context data
      # @param requested_by [User] The user who triggered the request (optional)
      # @return [Ai::ApprovalRequest, nil] nil in core mode
      def request_approval(agent:, action_type:, description:, request_data: {}, requested_by: nil)
        return nil unless self.class.business_loaded?

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
        return [] unless self.class.business_loaded?

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
        return false unless self.class.business_loaded?
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
        return false unless self.class.business_loaded?
        return false unless request.account_id == account.id
        return false unless request.pending?
        return false unless request.can_approve?(approver)

        request.record_decision!(approver: approver, decision: "rejected", comments: comments)
        true
      end

      # Expire overdue requests
      # No-op in core mode (no requests to expire).
      def expire_overdue!
        return 0 unless self.class.business_loaded?

        Ai::ApprovalRequest
          .where(account_id: account.id)
          .pending
          .where("expires_at <= ?", Time.current)
          .find_each do |request|
            request.update!(status: "expired", completed_at: Time.current)
          end
      end

      private

      def find_or_create_chain(action_type)
        Ai::ApprovalChain.find_or_create_by!(
          account_id: account.id,
          name: "autonomy_#{action_type}"
        ) do |chain|
          chain.trigger_type = "autonomy_action"
          chain.status = "active"
          chain.timeout_hours = 24
          chain.steps = [{ "name" => "autonomy_approval", "approvers" => ["*"], "required_approvals" => 1 }]
        end
      end
    end
  end
end
