# frozen_string_literal: true

module Ai
  module Tools
    # Tools a caller owns that the platform registry does not (D2 review F3) —
    # today the Ralph git tools, bound to one loop's own repository.
    #
    # A local tool used to be an executor the tool bridge called directly, so it
    # skipped every guard a registry call gets and could shadow a registry verb
    # by name. A binding closes both:
    #
    # - REGISTRATION refuses a name that collides with a registry verb. A local
    #   tool can never stand in for a platform tool, whatever it is called.
    # - DISPATCH goes through McpPlatformToolRegistrar.run_guarded, the runner a
    #   registry call uses: the tool's permission, the per-agent rate limit and
    #   the audit line, then Ai::Tools::BaseTool#execute (canonical-principal
    #   refusal, instance deny overlay, declared-action governance, the
    #   AutonomyGate). Only the advertisement check is skipped: a local tool is
    #   not a registry entry, so there is no registry advertisement to consult.
    #
    # The tool class must therefore be a BaseTool. The model chooses the tool
    # name and its arguments; it never chooses the action (set from the name) or
    # the server-bound params (merged last), so a caller cannot redirect a call
    # at another loop or another verb.
    class LocalToolBinding
      attr_reader :tool_class, :definitions, :server_params, :names

      def initialize(tool_class:, definitions:, server_params: {})
        unless tool_class.is_a?(Class) && tool_class <= ::Ai::Tools::BaseTool
          raise ArgumentError, "#{tool_class.inspect} is not an Ai::Tools::BaseTool: a local tool runs " \
                               "through the same chokepoint as a registry tool"
        end

        @tool_class = tool_class
        @definitions = Array(definitions).map { |d| d.to_h.deep_symbolize_keys }.freeze
        @server_params = server_params.to_h.stringify_keys.freeze
        @names = @definitions.to_set { |d| d[:name].to_s }.freeze

        clash = @names.to_a & ::Ai::Tools::PlatformApiToolRegistry.all_tools.keys
        return if clash.empty?

        raise ArgumentError, "local tool name(s) #{clash.sort.join(', ')} collide with platform registry " \
                             "verbs; a local tool may not shadow a registry verb"
      end

      def owns?(name)
        @names.include?(name.to_s)
      end

      # One local call, through the registry's guarded runner. Permission and
      # rate-limit refusals come back as result envelopes, as the bridge renders
      # them for registry calls; anything else raises to the caller's rescue.
      def dispatch(name, arguments, account:, user:, agent:)
        args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments
        params = (args.is_a?(Hash) ? args.to_h.stringify_keys : {})
                   .merge(server_params)
                   .merge("action" => name.to_s)

        ::Ai::Tools::McpPlatformToolRegistrar.run_guarded(
          tool_class,
          tool_id: "local.#{name}", params: params, account: account,
          user: user, agent_id: agent&.id, mcp_agent: agent
        )
      rescue ::Mcp::ProtocolService::PermissionDeniedError => e
        { success: false, error: "Permission denied: #{e.message}" }
      rescue ::Ai::Introspection::RateLimiter::RateLimitExceeded => e
        { success: false, error: e.message }
      end
    end
  end
end
