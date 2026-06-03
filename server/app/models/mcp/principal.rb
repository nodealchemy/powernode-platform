# frozen_string_literal: true

module Mcp
  # The authenticated principal behind an MCP request — either a platform User
  # (OAuth) or a fleet NodeInstance (mTLS). Unifies the two so the auth concern,
  # session handling, and tool-catalog scoping read ONE interface instead of
  # branching user-vs-instance throughout sensitive auth code.
  #
  # Core must not depend on the system extension, so an instance is resolved via
  # an injectable resolver (set by the extension engine — the same DI seam as
  # Security::MtlsTrust.own_ca_provider). The resolver maps a verified client-cert
  # CN (= NodeInstance.id) to an instance-like object exposing #id, #account, and
  # (optionally) #declared_capabilities.
  class Principal
    class << self
      attr_writer :instance_resolver

      # Lambda(cn) -> instance-like | nil. Defaults to "no instances resolvable"
      # so a stock core install (no extension) simply never authenticates an
      # instance principal — fail-closed.
      def instance_resolver
        @instance_resolver ||= ->(_cn) { nil }
      end

      def reset!
        @instance_resolver = nil
        @tool_grant_resolver = nil
      end

      # Lambda(node_instance) -> Array<String> of allowed tool-name glob patterns
      # (e.g. "platform.system_*_read", "platform.health"). Injected by the
      # extension's instance-grant model. Default: DENY ALL — an instance with no
      # resolver or no grant gets no tools.
      attr_writer :tool_grant_resolver

      def tool_grant_resolver
        @tool_grant_resolver ||= ->(_instance) { [] }
      end

      def for_user(user)
        new(kind: :user, account: user.account, user: user, subject_id: user.id)
      end

      # @return [Principal, nil] nil when the CN resolves to no live instance
      #   (or no resolver is injected) — callers fall through to the OAuth path.
      def for_instance_cn(cn)
        instance = instance_resolver.call(cn)
        return nil if instance.nil?

        account = instance.try(:account)
        return nil if account.nil?

        new(kind: :instance, account: account, node_instance: instance, subject_id: instance.try(:id))
      end
    end

    attr_reader :kind, :account, :user, :node_instance, :subject_id

    def initialize(kind:, account:, subject_id:, user: nil, node_instance: nil)
      @kind = kind
      @account = account
      @subject_id = subject_id
      @user = user
      @node_instance = node_instance
    end

    def user?
      kind == :user
    end

    def instance?
      kind == :instance
    end

    # The capability tokens used to scope the tool catalog. nil => unrestricted
    # (users keep their existing permission-based behavior). For an instance, its
    # declared capabilities (an empty list scopes to read-shape/introspection
    # tools — default-deny on mutating tools).
    def capability_scope
      return nil if user?

      Array(node_instance.try(:declared_capabilities)).map(&:to_s)
    end

    # nil-safe tool authorization. Users are unrestricted (existing permission
    # behavior). Instances are DEFAULT-DENY: a tool is invocable only when it
    # matches one of the instance's granted patterns (from the injected resolver).
    def may_invoke?(tool_name)
      return true if user?

      name = tool_name.to_s
      granted_tool_patterns.any? { |p| ::File.fnmatch(p, name, ::File::FNM_EXTGLOB) }
    end

    # Filter a tool list (array of {"name"=>...} hashes or strings) to the
    # invocable subset. Users get the full list; instances get only granted tools.
    def filter_tools(tools)
      return tools if user?

      tools.select { |t| may_invoke?(tool_name_of(t)) }
    end

    def granted_tool_patterns
      return [] unless instance?

      Array(self.class.tool_grant_resolver.call(node_instance)).map(&:to_s)
    end

    private

    def tool_name_of(tool)
      tool.is_a?(Hash) ? (tool["name"] || tool[:name]) : tool
    end
  end
end
