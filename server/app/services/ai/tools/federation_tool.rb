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

      def execute(params:)
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
