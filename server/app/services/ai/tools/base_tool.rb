# frozen_string_literal: true

module Ai
  module Tools
    class BaseTool
      REQUIRED_PERMISSION = nil
      MAX_CALLS_PER_EXECUTION = 20

      class << self
        def definition
          raise NotImplementedError, "#{name} must implement .definition"
        end

        # Returns per-action tool definitions keyed by external registry name.
        # Single-action tools inherit this default which strips the :action param.
        # Multi-action tools override to provide focused per-action schemas.
        def action_definitions
          defn = definition
          params = (defn[:parameters] || {}).except(:action)
          { defn[:name] => { description: defn[:description], parameters: params } }
        end

        def permitted?(agent:)
          return true unless self::REQUIRED_PERMISSION
          return true unless agent
          return true unless agent.respond_to?(:account) && agent.account

          # A tool is permitted for an agent when any user in its account holds the
          # required permission. Use the canonical resolution (User#has_permission?) so
          # CODE-DEFINED role grants count — a raw RolePermission query only sees DB
          # grants and silently hides every code-defined-role permission (e.g.
          # ai.campaigns.*) from all agents, including the concierge. Accounts are small
          # (single-user in core mode), so the per-user check is cheap.
          agent.account.users.any? { |user| user.has_permission?(self::REQUIRED_PERMISSION) }
        rescue StandardError
          # If permission check fails, allow the tool — execution is already
          # gated by the triggering user's API-level authorization.
          true
        end

        def tool_name
          definition[:name]
        end
      end

      # `internal: true` marks an in-process system caller (autonomy
      # reconcilers, skill executors running without a user) that is trusted to
      # skip a tool's per-action permission gate. It must be passed EXPLICITLY:
      # a nil @user does NOT imply "internal", because an MCP instance
      # principal (mTLS node cert) also arrives with no user, and tools that
      # inferred "internal" from `user.nil?` silently handed those principals
      # every per-action permission. (IMP-9030413bc292)
      def initialize(account:, agent: nil, user: nil, internal: false)
        @account = account
        @agent = agent
        @user = user
        @internal = internal
      end

      # Optionally injected post-construction by McpPlatformToolRegistrar for an
      # instance principal (mTLS node cert; no User/Agent) so DevLoopTool#claimant_ref
      # can scope claims as "instance:<id>". Public writer (external caller);
      # nil for user/agent callers, whose paths are unchanged. (BUG-S)
      attr_writer :node_instance

      # Set by McpPlatformToolRegistrar when the caller is an instance principal
      # whose SPECIFIC tool name already passed Mcp::Principal#may_invoke? in
      # the streamable controller. Lets a tool tell a grant-gated instance call
      # apart from a bare no-user call — indistinguishable while both were just
      # "@user is nil". (IMP-9030413bc292; sibling of the BUG-S writer above.)
      attr_writer :instance_authorized

      def execute(params:)
        # Ahead of validation: the refusal is unconditional, so a malformed
        # destroy-shaped call must not come back as a params error instead.
        enforce_instance_deny_overlay!(params)
        validate_params!(params)
        enforce_guardrails!
        call(params)
      end

      protected

      # SECURITY (IMP-0e6b216de843): re-arm Mcp::Principal's destructive deny
      # overlay against the action that ACTUALLY runs, at every depth.
      #
      # The overlay is documented in mcp/principal.rb as the last remaining
      # control on an instance principal, and it is checked against a tool NAME
      # — once, in the streamable controller, for the FIRST tool invoked. Below
      # that hop it had no reach: a tool that delegates to a skill executor
      # (SdwanTool, SystemIngressTool) forwarded only `user:`, so the executor
      # saw a nil user, called every nested tool `internal: true`, and no nested
      # name was ever name-checked. A grant for one benign name therefore
      # reached whatever those executors nest — including a destroy-shaped tool
      # the overlay refuses unconditionally, by name, at the first hop.
      # Executors now carry the provenance (System::Ai::Skills::
      # BaseSkillExecutor#tool), and this is the fence it re-arms.
      #
      # Grant globs are deliberately NOT re-checked here. The operator granted a
      # composer; the steps that composer runs are its implementation, not
      # separately-granted surface, and re-checking them would make a production
      # grant depend on composer internals — it would break at runtime, silently,
      # whenever a composer changed a step. The overlay is the right bound for
      # nested work: deny wins over any grant, at any depth.
      #
      # At the first hop this is a no-op (the controller already refused the
      # name, and McpPlatformToolRegistrar#enforce_action_scope! pins the action
      # to it) — which also means it holds the line if that pin is ever removed.
      def enforce_instance_deny_overlay!(params)
        return unless instance_authorized?

        name = effective_action_name(params)
        return unless ::Mcp::Principal.destructive_tool?(name)

        Rails.logger.warn(
          "[BaseTool] Refused destroy-shaped action for instance principal: " \
          "tool=#{self.class.name} action=#{name}"
        )
        raise ::Mcp::ProtocolService::PermissionDeniedError,
              "Action '#{name}' is destroy-shaped and is denied to every instance " \
              "principal, whatever it was granted"
      end

      # Build a skill executor with THIS tool's caller context and hand it the
      # instance provenance. EVERY tool that routes an MCP action to a skill
      # executor must come through here.
      #
      # An executor built any other way sees only a nil user, cannot tell a
      # grant-gated instance principal from an in-process reconciler, and so
      # calls every tool it nests `internal: true` — silently re-opening the
      # bypass this closed. That is not hypothetical: the same drop existed
      # independently in three tools (SdwanTool, SystemIngressTool and
      # SystemFleetTool's seven sites), which is why it is one funnel now rather
      # than a rule to remember at each call site.
      #
      # `account:` is overridable because a call site may resolve the account
      # differently; everything else is fixed by construction.
      # (IMP-0e6b216de843)
      def build_skill_executor(executor_class, account: @account, **overrides)
        mark_instance_provenance(
          executor_class.new(account: account, agent: @agent, user: @user, **overrides)
        )
      end

      # Hand this call's INSTANCE provenance to a delegate the tool routes to
      # (a skill executor). Guarded, so reconciler and user calls are untouched
      # and their paths stay byte-for-byte unchanged. Without it the delegate
      # sees only a nil user and cannot tell a grant-gated instance principal
      # from an in-process caller — which is how a name-scoped grant turned into
      # a blanket internal bypass one hop down. (IMP-0e6b216de843)
      def mark_instance_provenance(target)
        return target unless instance_authorized?

        target.instance_authorized = true
        target.node_instance = node_instance if node_instance
        target
      end

      # What the deny overlay must be matched against: the routed action for a
      # multi-action tool, the tool's own name otherwise.
      def effective_action_name(params)
        supplied = params.is_a?(Hash) ? (params[:action] || params["action"]) : nil
        supplied.to_s.presence || self.class.definition[:name].to_s
      end

      def call(params)
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      def validate_params!(params)
        param_def = self.class.definition[:parameters]
        return unless param_def.is_a?(Hash)

        # Skip JSON Schema-style definitions (have :type key) — validated at action level
        return if param_def.key?(:type)

        required = param_def.select { |_, v| v.is_a?(Hash) && v[:required] }.keys
        missing = required.select { |k| params[k].blank? }
        raise ArgumentError, "Missing required parameters: #{missing.join(', ')}" if missing.any?
      end

      def enforce_guardrails!
        validate_account_context!
      end

      def validate_account_context!
        return unless account

        unless account.is_a?(Account) && account.persisted?
          raise ArgumentError, "Invalid account context for tool execution"
        end
      end

      def success_result(data)
        { success: true, data: data }
      end

      def error_result(message)
        { success: false, error: message }
      end

      # True only when the caller explicitly declared itself an in-process
      # system caller via `internal: true`.
      def internal?
        @internal == true
      end

      # True only when McpPlatformToolRegistrar marked this call as an instance
      # principal that already cleared the per-tool grant gate.
      def instance_authorized?
        @instance_authorized == true
      end

      private

      attr_reader :account, :agent, :user, :node_instance
    end
  end
end
