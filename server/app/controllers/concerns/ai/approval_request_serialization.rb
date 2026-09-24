# frozen_string_literal: true

module Ai
  # IMP-550e44e24220 — the single definition of the Ai::ApprovalRequest fields
  # the approval read surface emits: Ai::AutonomyApprovalActions#serialize_approval_request.
  #
  # This module originally shared its core payload with a second, independently
  # maintained serializer — Api::V1::Ai::GovernanceController#approval_request_json
  # — kept aligned only by "in parity with ..." comments. Two separate changes
  # (the request_data redaction and the execution_status/execution_error pair)
  # each had to be hand-applied to both copies, which was exactly the drift
  # vector this extraction closed: a redaction rule added to one copy would
  # leave the other endpoint serving secret-bearing request_data to an audience
  # defined by the approval permissions rather than by the permission that made
  # the original gated call. The governance approval_requests endpoints —
  # including that second serializer — were deleted in fc-12, so
  # Ai::AutonomyApprovalActions is now this module's sole consumer; there is no
  # longer a second surface to drift against.
  #
  # SCOPE — this owns the fields the autonomy surface's own additions build on
  # top of (the agent_*/action_* denormalisations, requested_by_id, total_steps,
  # deferred_operation, current_step_can_approve, and an approval_chain subset).
  # Kept as its own module rather than inlined, so the shared core stays a
  # single definition if a second approval read surface is ever added again.
  #
  # CORE_KEYS is public on purpose: the autonomy key-set pin spec
  # (spec/requests/api/v1/ai/autonomy_approval_key_set_spec.rb) derives its
  # oracle from it instead of hand-listing the fields, so a field added to the
  # core here is covered without touching that spec.
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
      requires_human_session
    ].freeze

    private

    # Keep in step with CORE_KEYS — the autonomy key-set pin spec asserts the
    # read surface emits every key listed there.
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
        created_at: request.created_at,
        # MCP identity plan R2: only a person, in their own session, decides it.
        requires_human_session: request.requires_human_session?
      }
    end
  end
end
