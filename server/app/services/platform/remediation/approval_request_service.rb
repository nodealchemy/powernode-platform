# frozen_string_literal: true

module Platform
  module Remediation
    # CORE'S ONE WRITE on the remediation front door (design §5.1): park a
    # decision about a component in front of a person.
    #
    # ── WHY THIS MINTS THE REQUEST DIRECTLY ─────────────────────────────────
    # The obvious seam, Ai::Approvals::Gateway#request!, is the wrong one HERE
    # and only here. It short-circuits to `decision: :proceed` with NO request
    # whenever the governance capability is absent, on the reasoning that in
    # single-operator core mode the requester IS the approver, so the caller
    # should just do the thing.
    #
    # This verb has nothing to do. Its entire product is the parked request —
    # design §5.1 is explicit that there is no `respond_to_approval` verb and
    # that answering stays operator-side. A short circuit would therefore
    # return `success` having created nothing and reached nobody: a false
    # success of exactly the shape this platform keeps rediscovering, and the
    # operator would never learn that the component needs a decision.
    #
    # So it takes the path Ai::AutonomyGate#create_approval_request! takes,
    # which parks on EVERY deployment: find-or-strengthen a chain, then
    # #create_request! on it. The decision side is not capability-gated either
    # (Ai::Autonomy::ApprovalWorkflowService's class comment records the
    # 2026-09-08 incident where it was), so a request parked here is decidable
    # wherever it is parked.
    #
    # ── SOURCE, AND WHAT HAPPENS ON APPROVAL ────────────────────────────────
    # source_type/source_id name the COMPONENT. Platform::ComponentStatus does
    # not implement #on_approval_decision, and that is deliberate rather than
    # an omission: approving this request must not actuate anything. Core
    # never constructs a proceed (Platform::Remediation::Lane), so there is no
    # executor to replay and nothing for the decision hook to run. The
    # approval's product is a decision an operator has recorded; the lane's
    # own gate is what acts on it. Ai::ApprovalRequest#notify_source_of_decision
    # skips a source that does not answer the hook, so this is a supported
    # shape and not an accident waiting to raise.
    #
    # ── DEDUPE ──────────────────────────────────────────────────────────────
    # Keyed on (component, signal_kind, fingerprint) over ACTIVE requests —
    # pending and not past expires_at. An agent that re-reads a component and
    # re-asks must not mint a second card for the same occurrence; an operator
    # facing a queue of identical cards stops reading the queue. A fingerprint
    # is the occurrence id the signal source supplies, so a genuinely NEW
    # occurrence of the same kind carries a new fingerprint and does get its
    # own card.
    class ApprovalRequestService
      CHAIN_NAME = "Component Remediation"
      STEP_NAME = "Operator Approval"
      SOURCE_TYPE = "Platform::ComponentStatus"
      DEFAULT_TIMEOUT_HOURS = 24

      Result = Struct.new(:approval_request, :deduplicated, keyword_init: true) do
        def deduplicated? = deduplicated == true
      end

      def initialize(account:)
        @account = account
      end

      # @param component_status [Platform::ComponentStatus]
      # @param signal_kind [String]
      # @param rationale [String] what the requester wants done and why
      # @param route [Hash, nil] a Platform::RemediationRouter result, when the
      #   caller already has one — carried into request_data so the card shows
      #   the lane, the policy and the runbook without a second resolution
      # @param requested_by [User, nil]
      # @param fingerprint [String, nil] the occurrence id to dedupe on
      # @return [Result]
      def request!(component_status:, signal_kind:, rationale:, route: nil,
                   requested_by: nil, fingerprint: nil)
        kind = signal_kind.to_s
        key = fingerprint.presence || derived_fingerprint(component_status, kind)

        existing = find_active(component_status, kind, key)
        return Result.new(approval_request: existing, deduplicated: true) if existing

        request = chain.create_request!(
          source_type: SOURCE_TYPE,
          source_id: component_status.id,
          description: description_for(component_status, kind, rationale),
          request_data: request_data_for(component_status, kind, rationale, route, key),
          requested_by: requested_by
        )
        Result.new(approval_request: request, deduplicated: false)
      end

      private

      attr_reader :account

      def chain
        @chain ||= ::Ai::ApprovalChain.find_or_strengthen!(
          account: account, name: CHAIN_NAME, step_name: STEP_NAME,
          approvers: [ "*" ], required_approvals: 1,
          defaults: {
            trigger_type: "manual", status: "active", is_sequential: true,
            timeout_hours: DEFAULT_TIMEOUT_HOURS, timeout_action: "reject"
          }
        )
      end

      # ACTIVE, not merely pending: a request past its expires_at is answered
      # by the hourly expiry sweep, not at read time, so it sits in `pending`
      # for up to an hour after it stopped being live. Deduping against those
      # would swallow a fresh request for as long as the stale one lingers.
      def find_active(component_status, kind, key)
        ::Ai::ApprovalRequest
          .where(account_id: account.id)
          .for_source(SOURCE_TYPE, component_status.id)
          .active
          .where("request_data ->> 'signal_kind' = ?", kind)
          .where("request_data ->> 'fingerprint' = ?", key)
          .order(created_at: :desc)
          .first
      end

      # When a source supplied no occurrence id, dedupe on the component and
      # the kind alone. Coarser, and deliberately so — the alternative is no
      # dedupe at all, which mints a card per call.
      def derived_fingerprint(component_status, kind)
        "#{component_status.component_kind}:#{component_status.component_ref}:#{kind}"
      end

      def description_for(component_status, kind, rationale)
        name = component_status.display_name.presence || component_status.component_ref
        "Remediate #{component_status.component_kind} #{name} (#{kind}): #{rationale}"
      end

      def request_data_for(component_status, kind, rationale, route, key)
        {
          action_type: "platform.component_remediation",
          signal_kind: kind,
          fingerprint: key,
          rationale: rationale,
          component_kind: component_status.component_kind,
          component_ref: component_status.component_ref,
          component_status_id: component_status.id,
          verdict: component_status.verdict,
          # The lane's own report, verbatim. The card is read by an audience
          # wider than the permission that requested it, so it carries what
          # the lane said rather than a paraphrase — including the refusal
          # reason, which is often the whole reason a person is being asked.
          lane_key: route && route[:lane_key],
          policy: route && route[:policy],
          can_proceed: route && route[:can_proceed],
          reason: route && route[:reason],
          runbook: route && route[:runbook]
        }.compact
      end
    end
  end
end
