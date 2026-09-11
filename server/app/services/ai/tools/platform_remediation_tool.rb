# frozen_string_literal: true

module Ai
  module Tools
    # THE MCP FACE of the remediation front door (design §5.1, increment A5).
    #
    #   get_remediation_route   read  — who, if anyone, may act on this signal
    #                                   for this component, and what do they say
    #   get_runbook             read  — what an operator should read about a kind
    #   request_approval        WRITE — park a decision in front of a person
    #
    # ── THERE IS NO `respond_to_approval` ───────────────────────────────────
    # Design §5.1, stated as a rule and not a gap: the gate mints approvals to
    # REACH a person, and an agent that can answer them has closed the loop on
    # itself. Answering stays operator-side, over REST and the page. Nothing
    # in this file decides an approval, and nothing in it actuates: core never
    # constructs a proceed (Platform::Remediation::Lane).
    #
    # ── WHY THE ACTION NAMES START WITH `get_` ──────────────────────────────
    # Mcp::ToolCatalog derives `annotations.readOnlyHint` from the FIRST
    # underscore-segment of the action name against READ_ONLY_ACTION_PREFIXES.
    # A read verb named `route_remediation` or `runbook_for` would be
    # advertised with no read-only hint at all, and a client that trusts the
    # hint would treat it as a possible write. The names are what makes the
    # annotation true, so they are chosen to be true rather than annotated
    # after the fact. `request_approval` correctly gets no hint, and is the
    # name design §5.1 uses verbatim.
    #
    # ── WHY `request_approval` IS DECLARED BUT NOT GATE-WIRED ───────────────
    # It is declared `mutating: true, action_category: "approval"` — so it can
    # never take BaseTool#execute's UNDECLARED path, which falls open with a
    # bare `return call(params)` and one telemetry row.
    #
    # It deliberately carries no executor_class/gate_context/on_proceed, so
    # BaseTool#gated_action? is false and Ai::AutonomyGate does not park it.
    # Wiring the gate here would be circular: the seeded policy row for the
    # `approval` category is `require_approval`, so a verb whose entire product
    # is a parked approval would itself park an approval, and the operator
    # would have to approve being asked. The permission check below is what
    # bounds it instead, and it is enforced on the ungated path where the call
    # actually runs.
    class PlatformRemediationTool < BaseTool
      # FLOOR — the bar for reaching the class at all. The same permission
      # increment A4's REST door checks for the status plane, so an operator
      # who can see a component on the page can also ask what would be done
      # about it. A different floor here would produce the worst kind of
      # surface: a component visible on the screen whose remediation front
      # door answers "permission denied" for no reason the operator can see.
      REQUIRED_PERMISSION = "platform.status.read"

      # Per-action bar above the floor. Parking a decision in front of a
      # person is an autonomy WRITE — it consumes an operator's attention and
      # creates a durable row someone has to dispose of — so it is priced at
      # the autonomy write permission rather than at the read floor.
      # Deliberately NOT "ai.autonomy.approve": that is the permission to
      # ANSWER an approval, and this verb must never imply it.
      ACTION_PERMISSIONS = {
        "request_approval" => "ai.autonomy.manage"
      }.freeze

      declare_action "get_remediation_route", mutating: false
      declare_action "get_runbook", mutating: false
      declare_action "request_approval", mutating: true, action_category: "approval"

      # THE UMBRELLA. BaseTool#validate_params! validates against THIS hash for
      # every action on the class, not against the per-action entry below, so
      # the only parameter it may mark required is the one every action needs:
      # `action` itself. Marking component_kind required here would make
      # get_runbook — which takes no component at all — raise before it ran.
      # Each action validates its own arguments in its own body instead, which
      # is the idiom the sibling multi-action tools use.
      def self.definition
        {
          name: "platform_remediation",
          description: "Remediation front door for the component status plane: resolve which " \
                       "lane may act on a component's signal, read the runbook for a signal " \
                       "kind, and park a remediation decision in front of an operator.",
          parameters: {
            action: { type: "string", required: true,
                      description: "Action: get_remediation_route, get_runbook, request_approval" },
            component_kind: { type: "string", required: false, description: "Registry kind, e.g. 'ai_provider'" },
            component_ref: { type: "string", required: false, description: "Stable component id within the kind" },
            signal_kind: { type: "string", required: false, description: "The signal kind, e.g. 'instance.silent'" },
            rationale: { type: "string", required: false, description: "For request_approval: what should be done and why" },
            fingerprint: { type: "string", required: false, description: "For request_approval: occurrence id to dedupe on" }
          }
        }
      end

      def self.action_definitions
        {
          "get_remediation_route" => {
            description: "Resolve the remediation front door for a component and a signal kind: " \
                         "which registered lane claims the signal, the policy and consent headroom " \
                         "that lane reports, its blast radius and environment ceiling, whether it " \
                         "can proceed, and the runbook. Read-only — core resolves and reports; it " \
                         "never acts and never constructs a proceed. A signal kind no lane claims " \
                         "returns state 'not_actuatable' with reason 'NoLaneForSignal', still " \
                         "carrying the runbook.",
            parameters: {
              component_kind: { type: "string", required: true, description: "Registry kind, e.g. 'ai_provider'" },
              component_ref: { type: "string", required: true, description: "Stable component id within the kind" },
              signal_kind: { type: "string", required: true, description: "The signal kind to route, e.g. 'instance.silent'" }
            }
          },
          "get_runbook" => {
            description: "The operator runbook bound to a signal kind. Returns kind 'doc' with a " \
                         "path and anchor, kind 'generator' with the executor that produces one, " \
                         "or kind 'none'. A 'none' answer says whether the kind is KNOWN — a kind " \
                         "deliberately marked undocumented is a decided question, an unregistered " \
                         "kind is a coverage gap, and the two are not the same answer.",
            parameters: {
              signal_kind: { type: "string", required: true, description: "The signal kind to look up" }
            }
          },
          "request_approval" => {
            description: "Park a remediation decision about a component in front of an operator. " \
                         "Creates one pending approval request referencing the component and the " \
                         "routed lane, and returns its id. It does NOT act and does NOT answer " \
                         "itself: answering is operator-side. A second identical call while the " \
                         "first request is still live returns that request rather than minting a " \
                         "duplicate.",
            parameters: {
              component_kind: { type: "string", required: true, description: "Registry kind" },
              component_ref: { type: "string", required: true, description: "Stable component id within the kind" },
              signal_kind: { type: "string", required: true, description: "The signal kind the decision is about" },
              rationale: { type: "string", required: true, description: "What should be done and why — the operator reads this" },
              fingerprint: { type: "string", required: false, description: "Occurrence id to dedupe on; defaults to component+kind" }
            }
          }
        }
      end

      protected

      def call(params)
        # ONE normalized action drives both the gate and the dispatch, so the
        # permission that was checked always belongs to the branch that runs.
        action = routed_action_name(params)

        unless action_permitted?(action)
          Rails.logger.warn(
            "[PlatformRemediationTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case action
        when "get_remediation_route" then get_remediation_route(params)
        when "get_runbook" then get_runbook(params)
        when "request_approval" then request_approval(params)
        else
          error_result("Unknown action: #{action}. Valid: #{self.class.declared_actions.keys.join(', ')}")
        end
      end

      private

      # === Actions ==========================================================

      def get_remediation_route(params)
        args = indifferent(params)
        component = find_component(args)
        return component if component.is_a?(Hash)

        success_result(
          component: component_descriptor(component),
          signal_kind: args["signal_kind"].to_s,
          route: ::Platform::RemediationRouter.route(component, signal_kind: args["signal_kind"])
        )
      end

      def get_runbook(params)
        kind = indifferent(params)["signal_kind"].to_s
        return error_result("signal_kind is required") if kind.blank?

        success_result(signal_kind: kind, runbook: ::Platform::Runbook::Registry.render(kind))
      end

      def request_approval(params)
        args = indifferent(params)
        rationale = args["rationale"].to_s.strip
        return error_result("rationale is required") if rationale.blank?

        component = find_component(args)
        return component if component.is_a?(Hash)

        signal_kind = args["signal_kind"].to_s
        # Routed FIRST, so the card carries the lane's own report — including
        # its refusal reason, which is usually why a person is being asked at
        # all. Routing is a read; it neither authorizes nor performs anything.
        route = ::Platform::RemediationRouter.route(component, signal_kind: signal_kind)

        result = ::Platform::Remediation::ApprovalRequestService
                   .new(account: account)
                   .request!(component_status: component, signal_kind: signal_kind,
                             rationale: rationale, route: route,
                             requested_by: user, fingerprint: args["fingerprint"].presence,
                             call_origin: call_origin, agent: agent)

        request = result.approval_request
        success_result(
          approval_request_id: request.id,
          request_id: request.request_id,
          # SCOPED, not `status`. The bare noun is the incident shape this
          # tool's own subject makes worst: a caller asking a remediation front
          # door for "the status" means the component's remediation state — the
          # rung under `route[:state]` — and would read the approval row's
          # lifecycle as the answer. Two different questions, one plausible key.
          approval_request_status: request.status,
          expires_at: request.expires_at,
          deduplicated: result.deduplicated?,
          component: component_descriptor(component),
          signal_kind: signal_kind,
          route: route
        )
      rescue ActiveRecord::RecordInvalid => e
        error_result("Could not park the approval: #{e.message}")
      end

      # Params arrive indifferent from McpPlatformToolRegistrar but
      # SYMBOL-keyed from a DeferredToolCall replay (it deep_symbolize_keys the
      # parked copy); string reads against the latter would silently see
      # nothing, and a component lookup that silently sees nothing returns
      # "no component status for /" rather than a missing-params error.
      def indifferent(params)
        raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        raw.with_indifferent_access
      end

      # === Lookup ===========================================================

      # Returns the row, or an error_result Hash the caller returns as-is.
      #
      # Scoped to this account's rows PLUS the shared (null-account) rows,
      # matching the model's own tenancy rule: a process-wide kind carries no
      # account and would be invisible to a strict account scope.
      def find_component(args)
        kind = args["component_kind"].to_s
        ref = args["component_ref"].to_s
        return error_result("component_kind and component_ref are required") if kind.blank? || ref.blank?

        row = ::Platform::ComponentStatus
                .where(account_id: [ account&.id, nil ])
                .find_by(component_kind: kind, component_ref: ref)
        return error_result("No component status for #{kind}/#{ref}") if row.nil?

        row
      end

      def component_descriptor(component)
        {
          id: component.id,
          component_kind: component.component_kind,
          component_ref: component.component_ref,
          display_name: component.display_name,
          verdict: component.verdict,
          shared: component.account_id.nil?
        }
      end

      # === Per-action permission gating =====================================

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # The same two explicit bypasses the sibling tools carry, and no third:
      #
      #   internal?            an in-process system caller that opted in with
      #                        `internal: true`. Never inferred from a nil
      #                        user — an MCP instance principal also arrives
      #                        with none.
      #   instance_authorized? an mTLS node principal whose SPECIFIC tool name
      #                        already cleared Mcp::Principal#may_invoke?, and
      #                        whose action the registrar pins to that name.
      #
      # There is no `return true unless user.respond_to?(:has_permission?)`
      # arm. That arm fails OPEN, and REQUIRED_PERMISSION is not nil here, so
      # the registrar has already asked the question of any caller that gets
      # this far. A principal that cannot answer it is refused.
      def action_permitted?(action, required = required_perm_for(action))
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on
        # the MCP path coerces a permission answer, and a truthy non-boolean
        # must not read as a grant.
        user.has_permission?(required) == true
      end
    end
  end
end
