# frozen_string_literal: true

module Ai
  # Default content provider for approval requests sourced from
  # `Ai::DeferredOperation`. Reads `executor_class.preview(params)` to render
  # a generic title/message — extensions typically don't need their own
  # content provider unless they want richer formatting (icons, action_url
  # routing to a domain-specific page, etc.).
  #
  # All methods are class-level — providers are stateless.
  class DeferredOperationApprovalContent
    def self.notification_type
      "autonomy_approval_required"
    end

    def self.category
      "ai"
    end

    def self.action_url(_request)
      "/app/notifications"
    end

    def self.severity(request)
      op = deferred_for(request)
      return "info" unless op
      destructive_categories.any? { |frag| op.action_category.include?(frag) } ? "warning" : "info"
    end

    def self.title(request, _step)
      op = deferred_for(request)
      return "Approval needed" unless op

      preview = safe_preview(request, op)
      collapse_lines(preview[:summary]).presence || "Approval needed: #{op.action_category}"
    end

    def self.message(request, step)
      op = deferred_for(request)
      step_label = step["step_name"] || step["name"] || "Approval"
      total = request.step_statuses&.size || 1
      header = "#{step_label} (step #{request.current_step + 1}/#{total})"
      return header unless op

      preview = safe_preview(request, op)
      summary = collapse_lines(preview[:summary])
      impact = collapse_lines(preview[:impact])
      lines = [header]
      lines << summary if summary.present?
      lines << "Impact: #{impact}" if impact.present?
      lines << "Requested by: #{collapse_lines(op.requested_by&.email)}" if op.requested_by
      lines << "Agent: #{collapse_lines(op.ai_agent.name)}" if op.ai_agent
      lines.join("\n")
    end

    def self.metadata(request)
      op = deferred_for(request)
      return {} unless op
      {
        deferred_operation_id: op.id,
        action_category: op.action_category,
        executor_class: op.executor_class
      }
    end

    def self.deferred_for(request)
      return nil unless request.source_type == "Ai::DeferredOperation"
      ::Ai::DeferredOperation.find_by(id: request.source_id)
    end

    # `.title` and `.message` are two separate top-level entry points that
    # both render off the same deferred operation's preview within a single
    # notification pass (ApprovalRequestNotifier calls both back-to-back on
    # the same `request`). Since the cards sweep, `op.preview` is a
    # DB-backed executor round trip rather than string interpolation, so
    # computing it twice per render is a real cost — memoized here per
    # `request` instance (the one object both callers receive; `op` itself
    # is re-fetched fresh by `deferred_for` on every call, so it can't hold
    # the cache).
    #
    # Crypto-safety note (verified, not assumed): `op.preview` cannot
    # transitively include the executor's reveal-once minted secret.
    #
    # REVISED by IMP-4a5094b22df0. The old wording rested partly on
    # `System::Executors::Base.preview` hardcoding `deferred_operation: nil`,
    # so "a preview call can't reach a real operation's state at all" — that
    # sentence is obsolete and must not be quoted back, because the card path
    # now threads an account through in order to scope its labels. The claim
    # still holds, on grounds that were deliberately preserved:
    #
    #   1. STRUCTURAL, and the load-bearing one. What
    #      `Ai::DeferredOperation#preview` passes is an
    #      `Ai::DeferredOperation::PreviewContext` — an object carrying the
    #      account and nothing else — never the operation. `take_revealed_result!`
    #      is not a method on the thing the preview path holds, so no executor
    #      can call it, and one that tries raises NoMethodError, which
    #      `#preview`'s rescue turns into a generic card. The fail-safe posture
    #      the nil hardcoding used to provide is intact: a leak through this
    #      channel cannot silently start working.
    #   2. the slot is per-INSTANCE anyway. `@revealed_result` is set only
    #      inside `#execute_now!`, on the receiver, and is an in-memory ivar
    #      never persisted — while `deferred_for` below is a bare `find_by`, so
    #      the operation this memo caches a preview for is a different object
    #      from the one that executed. Independent of ground 1.
    #   3. the two paths are temporally exclusive — for THIS caller only.
    #      `notify_current_step!` refuses to run once the request is
    #      non-pending, and a request only goes non-pending through the same
    #      transition that triggers `execute_now!`. It does NOT generalise:
    #      Ai::AutonomyApprovalActions#serialize_deferred_operation is a second
    #      production caller of `op.preview` and runs on the approvals detail
    #      surface AFTER approval, on a completed operation. Grounds 1 and 2
    #      carry that path.
    #
    # So this memo cannot defeat the one-shot reveal — see IMP-6858255cea72's
    # reveal-once isolation spec, strengthened under IMP-4a5094b22df0 to fail
    # against an executor that DOES reach for execution state.
    #
    # Reuse across a later step-advance re-notification on the SAME request
    # object (a multi-step chain calls notify_current_step! again when
    # current_step changes) is also safe: source_type/source_id are fixed
    # for the whole chain, and nothing in the approval-advance flow
    # (record_decision!/process_decision!/advance_to_next_step!) writes to
    # the referenced DeferredOperation between steps. If that ever stops
    # holding, this needs a freshness key, not blind reuse.
    #
    # Not a per-accessor cache: title/message/severity/metadata never
    # receive `user` at all (see ApprovalRequestNotifier#notify_current_step!),
    # so there is no per-approver variance to collapse — see this file's
    # "N-approver identical content" spec, which uses approvers with
    # materially different permissions to give that claim teeth.
    PREVIEW_MEMO_IVAR = :@__deferred_operation_approval_content_preview

    def self.safe_preview(request, op)
      if request.instance_variable_defined?(PREVIEW_MEMO_IVAR)
        return request.instance_variable_get(PREVIEW_MEMO_IVAR)
      end

      preview = begin
        op.preview || {}
      rescue StandardError
        {}
      end
      request.instance_variable_set(PREVIEW_MEMO_IVAR, preview)
      preview
    end

    def self.destructive_categories
      %w[delete destroy terminate revoke decommission deprovision drop]
    end

    # The card's message is "\n"-joined, and its dynamic segments are
    # caller-supplied text replayed verbatim (preview fields interpolate
    # request params; Ai::Agent#name has no format validation) — so embedded
    # vertical whitespace would forge extra card lines on a HUMAN approval
    # gate (a spoofed "Impact:" line was live-reproduced). Collapse ALL line
    # structure to a single space here, at the one place the card is
    # composed: per-executor sanitization cannot close the hole, because a
    # newline-bearing name persisted by any create path resurfaces in later
    # unrelated delete/update cards (IMP-acb2e40960e7). Every dynamic
    # segment passes through this — including provably line-free ones like
    # the \A-anchored email — so the invariant is local, not spread across
    # distant validations.
    def self.collapse_lines(value)
      value.to_s.gsub(/[\r\n\v\f\u0085\u2028\u2029]+/, " ")
    end
  end
end
