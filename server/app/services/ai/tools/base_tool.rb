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
        validate_params!(params)
        enforce_guardrails!
        call(params)
      end

      protected

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
