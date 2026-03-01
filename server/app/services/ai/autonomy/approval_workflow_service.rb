# frozen_string_literal: true

module Ai
  module Autonomy
    class ApprovalWorkflowService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Create an approval request for an autonomy action
      # @param agent [Ai::Agent] The agent requesting the action
      # @param action_type [String] The action type
      # @param description [String] Description of what's being requested
      # @param request_data [Hash] Additional context data
      # @param requested_by [User] The user who triggered the request (optional)
      # @return [Ai::ApprovalRequest]
      def request_approval(agent:, action_type:, description:, request_data: {}, requested_by: nil)
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
      # @return [ActiveRecord::Relation]
      def pending_approvals
        Ai::ApprovalRequest
          .where(account_id: account.id)
          .pending
          .includes(:approval_chain)
          .order(created_at: :asc)
      end

      # Approve a pending request
      # @param request [Ai::ApprovalRequest] The request to approve
      # @param approver [User] The user approving
      # @param comments [String] Optional comments
      # @return [Boolean]
      def approve(request:, approver:, comments: nil)
        return false unless request.account_id == account.id
        return false unless request.pending?

        request.update!(status: "approved", completed_at: Time.current)
        request.decisions.create!(
          approver: approver,
          step_number: request.current_step || 0,
          decision: "approved",
          comments: comments
        )
        true
      end

      # Reject a pending request
      # @param request [Ai::ApprovalRequest] The request to reject
      # @param approver [User] The user rejecting
      # @param comments [String] Optional comments
      # @return [Boolean]
      def reject(request:, approver:, comments: nil)
        return false unless request.account_id == account.id
        return false unless request.pending?

        request.update!(status: "rejected", completed_at: Time.current)
        request.decisions.create!(
          approver: approver,
          step_number: request.current_step || 0,
          decision: "rejected",
          comments: comments
        )
        true
      end

      # Expire overdue requests
      def expire_overdue!
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
