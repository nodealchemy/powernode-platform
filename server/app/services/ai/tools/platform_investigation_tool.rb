# frozen_string_literal: true

module Ai
  module Tools
    # THE MCP FACE of the investigation (design §5.3, increment A6).
    #
    #   platform_investigate   WRITE — open an investigation of one component
    #   get_investigation      read  — the evidence, hypotheses and conclusion
    #   get_investigations     read  — this account's investigations
    #
    # ── WHY `platform_investigate` IS A WRITE ───────────────────────────────
    # It creates a durable row, assembles evidence (which reads across several
    # subsystems), and — through `InvestigationService#open!`, not through this
    # tool — enqueues `PlatformInvestigationJob`, which spends an LLM call.
    # `Mcp::ToolCatalog` derives
    # `annotations.readOnlyHint` from the first underscore-segment of the
    # action name, so the two read verbs are named `get_*` to make that
    # annotation TRUE rather than annotated after the fact, and the write verb
    # is not — which is the name design §5.3 uses for the operator's
    # "Investigate" button.
    #
    # ── IT OPENS; IT DOES NOT CONCLUDE ──────────────────────────────────────
    # The verb returns as soon as the evidence is recorded. Ranking is an LLM
    # call against a canonical agent and belongs in the worker
    # (`PlatformInvestigationJob`), never in the thread serving this call. An
    # investigation that comes back `open` with evidence and no hypotheses is
    # the normal, correct result of this verb.
    #
    # ── THE BOUNDS ARE THE SERVICE'S, NOT THIS TOOL'S ───────────────────────
    # The open-fingerprint rule and the per-account daily cap live in
    # `Platform::InvestigationService` and are enforced there, so the MCP path,
    # the automatic triggers and any future REST door are bounded by ONE rule.
    # A cap re-implemented here would be a second, weaker cap in front of the
    # real one — and the one an agent could get around by using another door.
    class PlatformInvestigationTool < BaseTool
      # FLOOR — the same permission the status plane's REST door checks, so an
      # operator who can see a component on the page can ask about it. A
      # different floor would produce a component visible on the screen whose
      # investigation verb refuses for no reason the operator can see.
      REQUIRED_PERMISSION = "platform.status.read"

      # Opening an investigation spends money (an LLM call) and creates a row
      # somebody has to dispose of, so it is priced above the read floor at the
      # autonomy write permission. Deliberately NOT an approval permission:
      # this verb parks no decision in front of anyone.
      ACTION_PERMISSIONS = {
        "platform_investigate" => "ai.autonomy.manage"
      }.freeze

      declare_action "platform_investigate", mutating: true, action_category: "investigation"
      declare_action "get_investigation", mutating: false
      declare_action "get_investigations", mutating: false

      # THE UMBRELLA. BaseTool#validate_params! validates against this hash for
      # every action on the class, so the only parameter it may mark required
      # is `action` itself — `get_investigations` takes no component at all,
      # and marking component_kind required here would make it raise before it
      # ran. Each action validates its own arguments in its own body.
      def self.definition
        {
          name: "platform_investigation",
          description: "Investigate why a component of the status plane is failing: open an " \
                       "investigation that assembles the evidence around the failure, and read " \
                       "the hypotheses and conclusion it produced.",
          parameters: {
            action: { type: "string", required: true,
                      description: "Action: platform_investigate, get_investigation, get_investigations" },
            component_kind: { type: "string", required: false, description: "Registry kind, e.g. 'docker_host'" },
            component_ref: { type: "string", required: false, description: "Stable component id within the kind" },
            investigation_id: { type: "string", required: false, description: "For get_investigation" },
            status: { type: "string", required: false, description: "For get_investigations: open, completed, failed, abandoned" },
            limit: { type: "integer", required: false, description: "For get_investigations, default 20" }
          }
        }
      end

      def self.action_definitions
        {
          "platform_investigate" => {
            description: "Open an investigation of one component. Assembles the evidence that " \
                         "existed around the failure — the component's conditions, its dependency " \
                         "chain with each neighbour's verdict, its status events in the window, " \
                         "cross-system correlations, matching learnings, and whatever module and " \
                         "remediation history is registered — records it, and returns the open " \
                         "investigation. Hypothesis ranking happens in the worker, so the returned " \
                         "investigation normally has evidence and no hypotheses yet. Bounded: one " \
                         "open investigation per component, and a per-account daily cap. A refusal " \
                         "names which bound it hit.",
            parameters: {
              component_kind: { type: "string", required: true, description: "Registry kind" },
              component_ref: { type: "string", required: true, description: "Stable component id within the kind" }
            }
          },
          "get_investigation" => {
            description: "One investigation by id: its trigger, status, assembled evidence, ranked " \
                         "hypotheses with confidence, and conclusion. Confidence carries a STATE as " \
                         "well as a number — 'not_measured' when the evidence set was empty, which " \
                         "is not the same answer as a confidence of 0.",
            parameters: {
              investigation_id: { type: "string", required: true, description: "The investigation id" }
            }
          },
          "get_investigations" => {
            description: "This account's investigations, newest first, optionally filtered by " \
                         "status or by component.",
            parameters: {
              component_kind: { type: "string", required: false, description: "Filter by kind" },
              component_ref: { type: "string", required: false, description: "Filter by component id" },
              status: { type: "string", required: false, description: "open, completed, failed or abandoned" },
              limit: { type: "integer", required: false, description: "Default 20, max 100" }
            }
          }
        }
      end

      protected

      def call(params)
        action = routed_action_name(params)

        unless action_permitted?(action)
          # `try`, not `&.`, for the principal id: the principal that reaches
          # this branch is by definition one that could not answer
          # `has_permission?`, and a log line must never be the thing that turns
          # a refusal into a 500.
          Rails.logger.warn(
            "[PlatformInvestigationTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user.try(:id)}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case action
        when "platform_investigate" then platform_investigate(params)
        when "get_investigation" then get_investigation(params)
        when "get_investigations" then get_investigations(params)
        else
          error_result("Unknown action: #{action}. Valid: #{self.class.declared_actions.keys.join(', ')}")
        end
      end

      private

      # === Actions ==========================================================

      def platform_investigate(params)
        args = indifferent(params)
        component = find_component(args)
        return component if component.is_a?(Hash)

        result = ::Platform::InvestigationService.new(account: account).open!(
          component, trigger: ::Platform::Investigation::TRIGGER_OPERATOR
        )

        if result[:refused]
          return success_result(opened: false, refused: result[:refused],
                                component: component_descriptor(component),
                                daily_cap: ::Platform::InvestigationService.daily_cap)
        end

        success_result(opened: true, investigation: serialize(result[:investigation]),
                       component: component_descriptor(component))
      end

      def get_investigation(params)
        id = indifferent(params)["investigation_id"].to_s
        return error_result("investigation_id is required") if id.blank?

        investigation = scope.find_by(id: id)
        return error_result("No investigation #{id}") if investigation.nil?

        success_result(investigation: serialize(investigation, include_evidence: true))
      end

      def get_investigations(params)
        args = indifferent(params)
        limit = args["limit"].present? ? [ args["limit"].to_i, 100 ].min : 20
        rows = scope.recent_first
        rows = rows.where(status: args["status"]) if args["status"].present?
        if args["component_kind"].present?
          rows = rows.where(component_kind: args["component_kind"])
          rows = rows.where(component_ref: args["component_ref"]) if args["component_ref"].present?
        end

        success_result(investigations: rows.limit(limit).map { |row| serialize(row) }, count: rows.limit(limit).size)
      end

      # === Lookup ===========================================================

      # This account's investigations PLUS the shared (null-account) ones,
      # matching the component model's own tenancy rule: a process-wide kind
      # carries no account and would be invisible to a strict scope.
      def scope
        ::Platform::Investigation.where(account_id: [ account&.id, nil ])
      end

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

      def serialize(investigation, include_evidence: false)
        base = {
          id: investigation.id,
          component_kind: investigation.component_kind,
          component_ref: investigation.component_ref,
          trigger: investigation.trigger,
          status: investigation.status,
          hypotheses: investigation.hypotheses,
          conclusion: investigation.conclusion,
          agent_id: investigation.agent_id,
          started_at: investigation.started_at,
          completed_at: investigation.completed_at
        }
        include_evidence ? base.merge(evidence: investigation.evidence) : base
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

      # Params arrive indifferent from McpPlatformToolRegistrar but
      # SYMBOL-keyed from a DeferredToolCall replay, so string reads against
      # the latter would silently see nothing.
      def indifferent(params)
        raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        raw.with_indifferent_access
      end

      # === Per-action permission gating =====================================

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # The same two explicit bypasses the sibling tools carry, and no third.
      # There is deliberately no "unless user.respond_to?" arm: that arm fails
      # OPEN, and a principal that cannot answer the permission question is
      # refused rather than admitted.
      def action_permitted?(action, required = required_perm_for(action))
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required) == true
      end
    end
  end
end
