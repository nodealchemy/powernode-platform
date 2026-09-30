# frozen_string_literal: true

module Ai
  module Approvals
    # THE builder of the principal block a parked Ai::DeferredOperation records
    # (IMP-a33f7a833313). One author for two things every park path needs:
    #
    #   .descriptor  WHO asked, in the shape Ai::Executors::DeferredToolCall
    #                rebuilds and AgentAutonomyTool#originated_by_caller? reads —
    #                minted from the parker's OWN state, never from anything a
    #                caller supplies.
    #   .stamp       the executor params with that block under KEY, replacing
    #                any `principal` the params already carry.
    #
    # Every park records it the same way, whether the gate is the generic
    # replay (BaseTool#deferred_tool_call_context, which also packs the call
    # for DeferredToolCall), a tool-specific gate_context, a hand-placed
    # Ai::AutonomyGate.evaluate in a tool (SdwanTool#gated_result,
    # DockerProvisioningTool#gated) or a skill executor's own gate — so a reader
    # scoping rows to a principal (get_approval_request today,
    # list_deferred_operations next) finds it at ONE key on every row.
    #
    # `internal` rides ALONGSIDE the kind rather than as a kind of its own,
    # because the two are orthogonal at depth: a skill executor nests every
    # tool with `internal: internal_caller?` while still forwarding the
    # caller's user/agent, so a nested hop is routinely BOTH `agent` and
    # internal. Recording only the kind would rebuild a strictly WEAKER tool
    # on replay, and a tool enforcing per-action permissions with
    # `return true if internal?` would then refuse the action an operator had
    # just approved — the approval silently becoming a no-op.
    #
    # An instance principal carries no User, and a nil user is NOT evidence of
    # an in-process caller (IMP-9030413bc292) — `internal` has to have been
    # passed explicitly. Anything else is "unattributed"; the generic replay
    # refuses to park such a call (its executor could never rehydrate it),
    # while a tool-specific park records the descriptor as-is, since its
    # executor does not rebuild the caller. That arm is reachable: a
    # FEDERATION principal arrives instance-authorized with no node instance,
    # because the controller passes `restricted?` rather than `instance?`.
    module ParkPrincipal
      KEY = "principal"

      module_function

      # The block, plus the door the call came through (MCP identity plan #6):
      # attribution on the parked approval and on its replay. `origin` is nil
      # for an unmarked call.
      def descriptor(user:, agent:, internal:, instance_authorized:, node_instance:,
                     call_origin: nil, action: nil, session_label: nil)
        shape(user: user, agent: agent, internal: internal, instance_authorized: instance_authorized,
              node_instance: node_instance, action: action, session_label: session_label)
          .merge("origin" => call_origin)
      end

      def shape(user:, agent:, internal:, instance_authorized:, node_instance:, action: nil, session_label: nil)
        if instance_authorized
          if node_instance
            return { "kind" => "instance", "node_instance_id" => node_instance.id,
                     "granted_tool_name" => granted_tool_name_for(action) }
                   .merge(session_label.present? ? { "session_label" => session_label } : {})
          end

          { "kind" => "unattributed", "detail" => "restricted principal with no node instance" }
        elsif user
          { "kind" => "user", "user_id" => user.id, "agent_id" => agent&.id, "internal" => internal == true }
        elsif agent
          { "kind" => "agent", "agent_id" => agent.id, "internal" => internal == true }
        elsif internal
          { "kind" => "internal" }
        else
          { "kind" => "unattributed", "detail" => "no user, agent or explicit internal flag" }
        end
      end

      # WHICH NAME the instance grant was actually checked against on the first
      # hop. StreamableHttpController asks `may_invoke?("platform.<tool_name>")`
      # — the advertised REGISTRY KEY — and McpPlatformToolRegistrar#
      # enforce_action_scope! then pins the action to
      # `ACTION_ALIASES.fetch(tool_name, tool_name)`, i.e. the alias TARGET. For
      # the aliased keys the routed action is therefore NOT the granted name:
      # a call granted as "platform.code_upsert_node" runs as "upsert_node", and
      # re-asking `may_invoke?("platform.upsert_node")` on replay matches no
      # realistic glob and would refuse every approved replay of an aliased
      # mutating action. Inverting the table (values are unique) recovers the
      # name the grant was read against; an unaliased action is its own name.
      def granted_tool_name_for(action)
        return nil if action.blank?

        ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.key(action.to_s) || action.to_s
      end

      # The executor params with the block under KEY. Always OVERWRITES: a
      # `principal` the params already carry is dropped in every key shape a
      # Hash can hold it (a symbol and a string key both serialize to the same
      # JSON member, and the JSONB column keeps whichever lands last), so a
      # gate context that passes caller params through cannot describe the
      # caller. A nil or non-Hash `executor_params` stamps an empty hash.
      def stamp(executor_params, descriptor)
        raw = executor_params.respond_to?(:to_unsafe_h) ? executor_params.to_unsafe_h : executor_params
        base = raw.is_a?(::Hash) ? raw : {}
        base.reject { |key, _| key.to_s == KEY }.merge(KEY => descriptor)
      end

      # The block a stored row carries, or nil — read the way every reader
      # should, off the operation's params.
      def recorded(params)
        return nil unless params.is_a?(::Hash)

        block = params[KEY] || params[KEY.to_sym]
        block.is_a?(::Hash) ? block : nil
      end
    end
  end
end
