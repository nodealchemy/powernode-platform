# frozen_string_literal: true

module Ai
  # IMP-550e44e24220 — the single definition of the Ai::ApprovalRequest fields
  # that BOTH approval read surfaces emit:
  #
  #   Api::V1::Ai::GovernanceController#approval_request_json
  #   Ai::AutonomyApprovalActions#serialize_approval_request
  #
  # Before this, the two were independent hash literals kept aligned by "in
  # parity with ..." comments. Two separate changes — the request_data
  # redaction and the execution_status/execution_error pair — each had to be
  # hand-applied to both copies. That is the drift vector the redaction work
  # exists to close: a redaction rule added to one copy leaves the other
  # endpoint serving secret-bearing request_data to an audience defined by the
  # approval permissions rather than by the permission that made the original
  # gated call.
  #
  # SCOPE — this owns the shared core only, NOT the whole payload. The two
  # surfaces legitimately differ beyond it and are not being unified:
  #
  #   governance only : updated_at, and the full approval_chain (trigger_type,
  #                     trigger_conditions, usage_count, ...)
  #   autonomy only   : the agent_*/action_* denormalisations, requested_by_id,
  #                     total_steps, deferred_operation, current_step_can_approve,
  #                     and an approval_chain subset carrying timeout_action
  #
  # Those differences are pre-existing and consumer-visible, so collapsing them
  # would change both endpoints' responses. Each controller therefore merges its
  # own extras onto this core.
  #
  # CORE_KEYS is public on purpose: the parity spec derives its oracle from it
  # instead of hand-listing the fields, so a field added to the core here is
  # covered without touching the spec.
  module ApprovalRequestSerialization
    extend ActiveSupport::Concern

    CORE_KEYS = %i[
      id
      request_id
      status
      source_type
      source_id
      description
      request_data
      current_step
      execution_status
      execution_error
      expires_at
      completed_at
      created_at
    ].freeze

    private

    # Keep in step with CORE_KEYS — the parity spec asserts both read surfaces
    # emit every key listed there, so a field added to one must be added to the
    # other.
    def approval_request_core(request)
      {
        id: request.id,
        request_id: request.request_id,
        status: request.status,
        source_type: request.source_type,
        source_id: request.source_id,
        description: request.description,
        # Filtered at the READ, not only at Ai::AutonomyGate's write:
        # request_data has producers besides the gate (Ai::GovernanceService,
        # Ai::Approvals::Gateway, the mission orchestrator), and rows written
        # before the gate started redacting still hold plaintext — the read is
        # the only surface that covers those retroactively. Callers wrap
        # serialization in Ai::SensitiveParams.batch so the pattern is resolved
        # once per page rather than once per row (IMP-77645b94151e).
        request_data: ::Ai::SensitiveParams.filter(request.request_data),
        current_step: request.current_step,
        # IMP-4bbb4227ac8a — declared post-approval execution outcome. Without
        # these an approved-but-failed action is indistinguishable from an
        # approved-and-done one on every approvals surface.
        execution_status: request.execution_status,
        execution_error: request.execution_error,
        expires_at: request.expires_at,
        completed_at: request.completed_at,
        created_at: request.created_at
      }
    end
  end
end
