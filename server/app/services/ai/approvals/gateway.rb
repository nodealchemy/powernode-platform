# frozen_string_literal: true

module Ai
  module Approvals
    # The single entry/exit point for human-approval gates.
    #
    # The platform grew ~12 separate approval mechanisms (MissionApproval,
    # ParkedQuestion, AgentProposal, CampaignProposal, ImprovementRecommendation,
    # plan approval, the ApprovalRequest chain, …). This facade is the canonical
    # seam they unify onto, one consumer at a time. It wraps the existing
    # Ai::ApprovalChain / Ai::ApprovalRequest machinery when a governance extension
    # is present, and auto-proceeds in single-operator core mode (the requester IS
    # the approver — mirrors Ai::AutonomyGate#require_approval_or_proceed).
    #
    # Approvable contract: a model passed as `approvable:` SHOULD implement
    #   #on_approval_decision(approval_request)
    # which Ai::ApprovalRequest#notify_source_of_decision invokes when the request
    # is resolved (see Ai::DeferredOperation, Ai::CampaignLand). In core mode no
    # ApprovalRequest is created, so the caller handles the `:proceed` result by
    # performing the same action it would run on approval.
    #
    # That hook MUST report what it did, returning
    # Ai::ApprovalRequest::DISPATCH_EXECUTED when it ran its decision branch and
    # ::DISPATCH_NOOP when it deliberately did not (already resolved, cancelled,
    # no longer parked at this gate). Returning without raising is NOT a claim
    # that anything happened, and an implementation that says nothing leaves the
    # request's execution_status nil rather than asserting a success nobody
    # verified (IMP-5547989e2bbd).
    #
    # Additive + reversible: this migrates zero existing consumers — it only gives
    # all flows one documented entry point. Consumers opt in incrementally.
    class Gateway
      # decision: :pending (request created, awaiting humans) | :proceed (core
      # auto-proceed — no gate). approval_request is nil when :proceed.
      Result = Data.define(:decision, :approval_request) do
        def pending? = decision == :pending
        def proceed? = decision == :proceed
      end

      def initialize(account:)
        @account = account
      end

      # Single source of truth for the core-mode short-circuit.
      def self.governance_enabled?
        Ai::Autonomy::ApprovalWorkflowService.governance_enabled?
      end

      # Open a human-approval gate for `approvable`.
      #
      # @param approvable [#id] model being gated (becomes source_type/source_id)
      # @param kind [String, Symbol] logical gate name (chain name + action_type)
      # @param description [String, nil]
      # @param approvers [Array] approver specs ("*" | user-id | {type:…}); default ["*"]
      # @param required_approvals [Integer] signatures required (e.g. 2 = second-signature)
      # @param timeout_hours [Integer]
      # @param request_data [Hash] extra context merged into the request
      # @param requested_by [User, nil]
      # @return [Result]
      def request!(approvable:, kind:, description: nil, approvers: [ "*" ], required_approvals: 1,
                   timeout_hours: 24, request_data: {}, requested_by: nil)
        return Result.new(decision: :proceed, approval_request: nil) unless self.class.governance_enabled?

        chain = find_or_create_chain(kind, approvers, required_approvals, timeout_hours)
        request = chain.create_request!(
          source_type: approvable.class.name,
          source_id: approvable.id,
          description: description.presence || kind.to_s.humanize,
          request_data: request_data.merge(action_type: kind.to_s),
          requested_by: requested_by
        )
        Result.new(decision: :pending, approval_request: request)
      end

      # Resolve an open gate. Routes through the chain workflow so the multi-step
      # machinery runs and the approvable's #on_approval_decision is cascaded.
      # @param decision [String, Symbol] "approved" | "rejected"
      # @return [Boolean] whether the decision was recorded
      def resolve!(request:, decision:, by:, comments: nil)
        service = Ai::Autonomy::ApprovalWorkflowService.new(account: @account)
        case decision.to_s
        when "approved" then service.approve(request: request, approver: by, comments: comments)
        when "rejected" then service.reject(request: request, approver: by, comments: comments)
        else raise ArgumentError, "decision must be approved|rejected, got #{decision.inspect}"
        end
      end

      private

      def find_or_create_chain(kind, approvers, required_approvals, timeout_hours)
        Ai::ApprovalChain.find_or_strengthen!(
          account: @account, name: "gateway_#{kind}", step_name: kind.to_s,
          approvers: approvers, required_approvals: required_approvals,
          defaults: { trigger_type: "manual", status: "active", timeout_hours: timeout_hours }
        )
      end
    end
  end
end
