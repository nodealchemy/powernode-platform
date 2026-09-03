# frozen_string_literal: true

module Ai
  module Executors
    # THE generic Ai::AutonomyGate executor for a declared mutating MCP tool
    # action (APO-1b, IMP-ce0dcca3f19a). Design note:
    # docs/concepts/deferred-tool-call-replay.md
    #
    # Ai::Tools::BaseTool#execute is the chokepoint that routes a declared
    # action through the gate, and #gated_action? arms that gate only when the
    # declaration names an `executor_class` the gate can re-invoke after an
    # operator decides. Without a generic one, wiring the ~600 declarations
    # APO-1a produced (608 call sites on 2026-09-02, none gate-wired) means
    # authoring one bespoke executor per action — each re-solving the same hard
    # half: WHO asked.
    #
    # `Ai::DeferredOperation` records `requested_by` and `ai_agent` and nothing
    # else. An MCP instance principal (mTLS node cert) and a federation partner
    # carry NEITHER, so a call parked on their behalf loses its identity at the
    # moment it is parked, and a replay rebuilt with a nil user is read one hop
    # down as an in-process caller — which hands every nested tool the
    # `internal: true` bypass that IMP-0e6b216de843 closed at call time. This
    # carries the principal in the parked params and rebuilds it, so approval
    # runs as the ORIGINAL caller or does not run at all.
    #
    # Contract (same as every other gate executor):
    #
    #   .execute(params, deferred_operation:) → the replayed tool's own result
    #   .preview(params, deferred_operation:) → { summary:, impact: }
    #
    # Params (built by BaseTool#deferred_tool_call_context, JSONB round-tripped):
    #
    #   { "tool_class"  => "Ai::Tools::SystemFleetTool",
    #     "action"      => "system_terminate_instance",
    #     "tool_params" => { … the caller's params, verbatim … },
    #     "principal"   => { "kind" => "user"|"agent"|"instance"|"internal", … } }
    #
    # The caller's params ride under their own key, so nothing a caller supplies
    # can spoof the `principal` block: BaseTool mints that from its OWN
    # constructor state, never from params.
    #
    # CORE PURITY: `tool_class` is a string resolved through `safe_constantize`
    # and bounded by an ancestry check, so an extension's tool is replayable
    # without core naming it. The instance principal is rehydrated through
    # `Mcp::Principal.for_instance_cn` — the existing injectable resolver seam.
    class DeferredToolCall
      # A refusal is a RESULT, never a raise. Ai::DeferredOperation#execute_now!
      # turns a raise into `fail!` + re-raise out of
      # Ai::ApprovalRequest#notify_source_of_decision, which would make "this
      # principal is no longer allowed to do that" an exception on the
      # approver's decision path and lose the reason. Returned, it completes the
      # operation and records why in :result, where the approvals surface reads.
      REASON_UNREPLAYABLE_TOOL = "unreplayable_tool"
      REASON_PRINCIPAL_UNRESOLVABLE = "principal_unresolvable"
      REASON_PERMISSION_REVOKED = "permission_revoked"
      REASON_ACTION_MISMATCH = "action_mismatch"

      # Statuses of the operation being replayed that BaseTool#approved_replay?
      # accepts. Named here because this class is the one that sets the row on
      # the tool, and #execute_now! has already moved it to :executing by then.
      REPLAYABLE_STATUSES = %w[approved executing].freeze

      # What a rehydrated caller is. Not Mcp::Principal — that models an MCP
      # request's authenticated identity and has no notion of an Ai::Agent
      # caller, which is half of what reaches this gate.
      #
      # `internal` is orthogonal to `kind`, not a value of it: a nested hop is
      # routinely both an agent call and an in-process one (a skill executor
      # builds every tool it nests with `internal: internal_caller?` while
      # forwarding the caller's user/agent). Dropping it would rebuild a
      # strictly weaker tool than the one that parked the call.
      Caller = Struct.new(:kind, :user, :agent, :node_instance, :mcp_principal,
                          :internal, :granted_tool_name, keyword_init: true)

      class << self
        # Build the parked payload. Lives beside #execute so the wire shape has
        # exactly one author.
        def pack(tool_class:, action:, tool_params:, principal:)
          {
            "tool_class" => tool_class.to_s,
            "action" => action.to_s,
            "tool_params" => normalize(tool_params),
            "principal" => normalize(principal)
          }
        end

        def execute(params, deferred_operation:)
          call = normalize(params)
          account = deferred_operation.account

          tool_class = replayable_tool_class(call["tool_class"])
          if tool_class.nil?
            return refuse(REASON_UNREPLAYABLE_TOOL,
                          "#{call['tool_class'].inspect} is not a replayable tool")
          end

          principal_ctx = rehydrate_caller(call["principal"], account)
          if principal_ctx.nil?
            return refuse(REASON_PRINCIPAL_UNRESOLVABLE,
                          "the principal that requested this action can no longer be resolved")
          end

          unless authorized?(principal_ctx, tool_class, call["action"])
            return refuse(REASON_PERMISSION_REVOKED,
                          "the principal that requested this action no longer holds the " \
                          "permission it was authorised under")
          end

          replay(tool_class, principal_ctx, account, call, deferred_operation)
        rescue ::Mcp::ProtocolService::PermissionDeniedError => e
          # The deny overlay (or a nested one) refused the replay. Same class of
          # answer as a revoked grant, so it takes the same shape.
          refuse(REASON_PERMISSION_REVOKED, e.message)
        end

        # Approval-card content. `deferred_operation` here is an
        # Ai::DeferredOperation::PreviewContext (account and nothing else).
        #
        # Deliberately names the ACTION and the principal SHAPE only. The
        # caller's params are the one thing on this row that can hold minted
        # secret material, and Ai::SensitiveParams covers the copy in
        # request_data by KEY — a summary that interpolated them would put the
        # values on the card under a key of this class's choosing, outside that
        # cover.
        def preview(params, deferred_operation: nil)
          call = normalize(params)

          {
            summary: "Run #{call['action'].presence || 'tool action'} " \
                     "(#{call['tool_class'].presence || 'unknown tool'})",
            impact: "Replayed on approval as the #{principal_kind(call)} principal that " \
                    "requested it; refused if that principal has since lost the permission."
          }
        end

        private

        def replay(tool_class, principal_ctx, account, call, deferred_operation)
          tool = build_tool(tool_class, principal_ctx, account)
          replay_params = symbolize(call["tool_params"])

          # The permission re-check above is keyed on the RECORDED action. If the
          # stored params would route #execute to a different one, the check
          # authorised something other than what is about to run.
          routed = tool.send(:routed_action_name, replay_params).to_s
          if call["action"].present? && routed != call["action"]
            return refuse(REASON_ACTION_MISMATCH,
                          "parked params route to #{routed.inspect}, not the approved " \
                          "#{call['action'].inspect}")
          end

          tool.replaying_operation = deferred_operation
          tool.execute(params: replay_params)
        end

        # An arbitrary class name off a JSONB column must not become a
        # `.new(account:).execute` on this path. Bounded to the chokepoint's own
        # hierarchy — which is also what guarantees the tool answers
        # `replaying_operation=` and re-applies the deny overlay.
        def replayable_tool_class(name)
          klass = name.to_s.presence&.safe_constantize
          return nil unless klass.is_a?(Class)
          return nil unless klass <= ::Ai::Tools::BaseTool

          klass
        end

        # Bounded to the operation's account in every arm. The gate opened this
        # operation in ONE account, and a principal outside it is not the
        # principal that asked. For an agent that bound is the account's
        # VISIBILITY (global canonicals plus its own rows), not ownership — see
        # #agent_for.
        def rehydrate_caller(principal, account)
          descriptor = normalize(principal)
          return nil if account.nil?

          case descriptor["kind"].to_s
          when "user"     then user_caller(descriptor, account)
          when "agent"    then agent_caller(descriptor, account)
          when "instance" then instance_caller(descriptor, account)
          when "internal" then Caller.new(kind: "internal")
          end
        end

        def user_caller(descriptor, account)
          user = account.users.find_by(id: descriptor["user_id"])
          return nil if user.nil?

          # An agent acting FOR a user is recorded as both; a missing agent row
          # does not invalidate the user, it just replays without it.
          Caller.new(kind: "user", user: user, agent: agent_for(descriptor, account),
                     internal: descriptor["internal"] ? true : false)
        end

        def agent_caller(descriptor, account)
          agent = agent_for(descriptor, account)
          return nil if agent.nil?

          Caller.new(kind: "agent", agent: agent, internal: descriptor["internal"] ? true : false)
        end

        # A FEDERATION principal reaches BaseTool as `instance_authorized` with
        # NO node instance (streamable_http_controller passes `restricted?`, not
        # `instance?`), so it lands here with a blank id and is refused. Core
        # holds no handle on the partner row from the tool seam; fail closed.
        def instance_caller(descriptor, account)
          cn = descriptor["node_instance_id"].to_s
          return nil if cn.blank?

          principal = ::Mcp::Principal.for_instance_cn(cn)
          return nil if principal.nil?
          return nil unless principal.account&.id == account.id

          Caller.new(kind: "instance", node_instance: principal.node_instance,
                     mcp_principal: principal,
                     granted_tool_name: descriptor["granted_tool_name"].presence)
        end

        # The account's VISIBILITY, not its ownership. Every official agent is a
        # GLOBAL canonical (account_id NULL — GloballyScopable, HIER-P1), and an
        # account customises one by cloning it; the canonical acting as the
        # caller of a gated verb is therefore the common case, and an ownership
        # match (`account_id: account.id`) broke BOTH arms for it, differently:
        # the agent arm refused `principal_unresolvable`, while the user arm (an
        # agent acting FOR a user — the shape MCP actually parks) treats a nil
        # agent as benign and replayed agent-LESS, so the approved write failed
        # SILENTLY in the tool body ("Agent not found") rather than refusing. A
        # clone replayed fine either way.
        # `for_account` is the same scope the tools' own agent resolution
        # reads through (Ai::Agent.resolve_for), and it keeps account rows
        # account-scoped: another account's agent, canonical-cloned or not, is
        # not visible here and still fails closed.
        def agent_for(descriptor, account)
          id = descriptor["agent_id"]
          return nil if id.blank?

          ::Ai::Agent.for_account(account.id).find_by(id: id)
        end

        # The SAME question each principal's own door asks, re-asked now — which
        # also means it is no STRICTER than that door. Note the agent arm is
        # INERT for a global canonical: BaseTool.permitted? returns true when the
        # agent has no account, so REASON_PERMISSION_REVOKED cannot fire for a
        # canonical principal. That fail-open is the first hop's, not one this
        # seam opens; closing it (evaluating REQUIRED_PERMISSION against the
        # OPERATION's account users) belongs with permitted?, since doing it only
        # here would refuse on replay what the park had allowed.
        def authorized?(principal_ctx, tool_class, action)
          case principal_ctx.kind
          when "user"
            required = tool_class::REQUIRED_PERMISSION
            required.nil? || principal_ctx.user.has_permission?(required)
          when "agent"
            tool_class.permitted?(agent: principal_ctx.agent)
          when "instance"
            # Grant globs AND the destroy-shaped deny overlay, against the name
            # the first hop was gated on — which is the RECORDED tool name, not
            # the routed action. McpPlatformToolRegistrar#enforce_action_scope!
            # pins the action to `ACTION_ALIASES.fetch(tool_name, tool_name)`,
            # the alias TARGET, so for the 25 aliased registry keys the two
            # differ (granted "platform.code_upsert_node" runs as
            # "upsert_node"). BaseTool#granted_tool_name_for records the former;
            # the action is the fallback for a row parked before it did.
            granted = principal_ctx.granted_tool_name.presence || action
            principal_ctx.mcp_principal.may_invoke?("platform.#{granted}")
          when "internal"
            # An in-process caller (a reconciler) holds no permission that could
            # be revoked. There is nothing to re-check — and nothing that a
            # revocation elsewhere should silently convert into a bypass, because
            # the flag is set by the constructing code, never by a request.
            true
          else
            false
          end
        end

        def build_tool(tool_class, principal_ctx, account)
          case principal_ctx.kind
          when "instance"
            tool = tool_class.new(account: account)
            tool.instance_authorized = true
            tool.node_instance = principal_ctx.node_instance
            tool
          when "internal"
            tool_class.new(account: account, internal: true)
          else
            # `internal:` is carried, not dropped. Rebuilding a nested hop
            # without it hands the tool's own #action_permitted? a shallower
            # call than the one that was approved, and a tool whose per-action
            # check opens with `return true if internal?` would refuse the
            # action the operator just granted. The re-check above is unchanged
            # by it: a user still needs the permission, an agent still needs
            # .permitted?.
            tool_class.new(account: account, user: principal_ctx.user,
                           agent: principal_ctx.agent,
                           internal: principal_ctx.internal ? true : false)
          end
        end

        def refuse(reason, message)
          {
            success: false,
            refused: true,
            reason: reason,
            error: "Refusing to replay the approved action: #{message}."
          }
        end

        def principal_kind(call)
          kind = normalize(call["principal"])["kind"].to_s
          kind.presence || "unattributed"
        end

        # JSONB hands these back with string keys, but the auto-approve branch
        # runs #execute_now! on the in-memory row, where ActiveRecord's json type
        # cast leaves an assigned Hash exactly as it was written. Both shapes
        # reach here; only one may leave.
        def normalize(value)
          raw = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
          return {} unless raw.is_a?(::Hash)

          raw.deep_stringify_keys
        end

        # Tool bodies and BaseTool#validate_params! read symbol keys — the shape
        # they were written against, and the shape the call had before it was
        # parked. Restoring it is what makes the round trip invisible to them.
        def symbolize(value)
          raw = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
          return {} unless raw.is_a?(::Hash)

          raw.deep_symbolize_keys
        end
      end
    end
  end
end
