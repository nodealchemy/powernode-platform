# frozen_string_literal: true

module Ai
  module Tools
    # Cross-plane MCP: invoke a tool on a federated peer Powernode deployment.
    #
    # This is the OUTBOUND / plane-addressing half of federation tool invocation —
    # the caller names a registered FederationPartner and a remote tool, and the
    # call is proxied to that partner's MCP endpoint (see
    # FederationPartner#invoke_remote_tool). The peer authenticates the shared
    # bearer token and runs the call as a default-deny federation principal on its
    # own account (McpTokenAuthentication#authenticate_via_federation_partner).
    #
    # Partners are account-scoped: a caller can only reach partners its own account
    # has registered. Registration + the shared secret are operator-configured
    # (FederationController), never minted here.
    class FederationTool < BaseTool
      REQUIRED_PERMISSION = "ai.federation.invoke"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "federation_invoke_tool", mutating: true
      declare_action "federation_list_partners", mutating: false

      # BaseTool.definition raises NotImplementedError, and McpPlatformToolRegistrar
      # calls it OUTSIDE its per-tool rescue (register_all!), so a tool missing this
      # aborts registration for every tool after it — and McpChannel#subscribed does
      # not rescue either, which took down the whole ActionCable MCP transport.
      def self.definition
        {
          name: "federation",
          description: "Cross-plane MCP: invoke a tool on, or list, this account's federated peer deployments",
          parameters: {
            action: { type: "string", required: true, description: "federation_invoke_tool | federation_list_partners" },
            partner_id: { type: "string", required: false, description: "FederationPartner id (or use organization_id)" },
            organization_id: { type: "string", required: false, description: "Partner organization id (alternative to partner_id)" },
            tool: { type: "string", required: false, description: "Remote MCP tool name to invoke, e.g. system_list_templates" },
            arguments: { type: "object", required: false, description: "Arguments object for the remote tool" }
          }
        }
      end

      def self.action_definitions
        {
          "federation_invoke_tool" => {
            description: "Invoke an MCP tool on a federated peer deployment (cross-plane). " \
                         "Identify the partner by partner_id or organization_id.",
            parameters: {
              partner_id: { type: "string", required: false, description: "FederationPartner id (or use organization_id)" },
              organization_id: { type: "string", required: false, description: "Partner organization id (alternative to partner_id)" },
              tool: { type: "string", required: true, description: "Remote MCP tool name to invoke, e.g. system_list_templates" },
              arguments: { type: "object", required: false, description: "Arguments object for the remote tool" }
            }
          },
          "federation_list_partners" => {
            description: "List this account's active federation partners that can be targeted for cross-plane calls.",
            parameters: {}
          }
        }
      end

      protected

      # THE HOIST (IMP-149b35e5f16f). BaseTool#execute reaches #call only for an
      # UNGATED action; a gated one returns from the gate branch without ever
      # entering the body below (base_tool.rb: "tools that enforce per-action
      # permissions INSIDE #call ... would lose that check the moment an action
      # is declared — a privilege escalation introduced by a safety control").
      #
      # `federation_invoke_tool` is already `declare_action ... mutating: true`;
      # it becomes gated the instant APO-1e adds the category/executor/context/
      # on_proceed quartet. Without this hoist that wiring would delete the
      # structural anti-relay refusal as a side effect and start PARKING
      # approvals for calls that are forbidden outright. Same shape as
      # SystemFleetTool#authorization_error.
      def authorization_error(_params)
        return nil unless instance_authorized?

        error_result("Outbound federation is not available to a federated or instance principal")
      end

      # #call, NOT #execute (IMP-149b35e5f16f). This class used to define
      # #execute and never call super, so it served every call OUTSIDE
      # BaseTool#execute — the one chokepoint that performs the declaration
      # lookup, re-arms Mcp::Principal's destructive deny overlay
      # (IMP-0e6b216de843) and runs #validate_params!. Its two declare_action
      # rows satisfied the completeness equality while governing nothing, on
      # the single tool that proxies ARBITRARY remote tool names. APO-1e's
      # fail-closed flip could not be honest with that exemption standing.
      #
      # The structural refusal below answers every restricted principal on the
      # path that REACHES this body, and what now runs ahead of it only ever
      # refuses (for an instance principal — the only caller the overlay
      # applies to — a destroy-shaped action name raises before arriving here).
      # But a GATED action returns from BaseTool#execute's gate branch (its
      # `return call(params) unless gated_action?(declaration)` is the last
      # line that can reach here) without ever calling #call, so the refusal is
      # also hoisted into #authorization_error above:
      # that is the seam BaseTool documents for exactly this, and keeping only
      # the #call copy would make APO-1e's gate wiring silently delete the
      # refusal. Both copies stand — the hoist is the load-bearing one.
      def call(params)
        # A restricted principal (federation peer or fleet instance) must NEVER
        # drive OUTBOUND federation — that would turn this plane into an open
        # cross-plane relay / SSRF pivot and spend its outbound credentials on a
        # remote caller's behalf. Structural refusal, independent of any grant.
        return error_result("Outbound federation is not available to a federated or instance principal") if instance_authorized?

        case params[:action] || params["action"]
        when "federation_invoke_tool" then invoke_tool(params)
        when "federation_list_partners" then list_partners
        else error_result("Unknown federation action")
        end
      end

      private

      def invoke_tool(params)
        partner = resolve_partner(params)
        return error_result("Federation partner not found or not active") unless partner

        tool = (params[:tool] || params["tool"]).to_s
        return error_result("tool is required") if tool.blank?

        result = partner.invoke_remote_tool(tool: tool, arguments: coerce_arguments(params))
        return error_result(result[:error]) unless result[:success]

        success_result(remote_result: result[:result], partner_id: partner.id)
      end

      def list_partners
        partners = FederationPartner.active.where(account: account).map do |p|
          {
            id: p.id,
            organization_id: p.organization_id,
            name: p.name,
            endpoint_url: p.endpoint_url,
            trust_level: p.trust_level,
            allowed_capabilities: p.allowed_capabilities
          }
        end
        success_result(partners: partners)
      end

      # Account-scoped so a caller can never address another tenant's partner.
      def resolve_partner(params)
        scope = FederationPartner.active.where(account: account)
        if (id = (params[:partner_id] || params["partner_id"]).presence)
          scope.find_by(id: id)
        elsif (org = (params[:organization_id] || params["organization_id"]).presence)
          scope.find_by(organization_id: org)
        end
      end

      def coerce_arguments(params)
        args = params[:arguments] || params["arguments"] || {}
        return args if args.is_a?(Hash)

        args.is_a?(String) ? (JSON.parse(args) rescue {}) : {}
      end
    end
  end
end
