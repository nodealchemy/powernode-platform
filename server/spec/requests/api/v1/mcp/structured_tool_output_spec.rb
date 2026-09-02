# frozen_string_literal: true

require "rails_helper"

# The tool registry has always carried an outputSchema, but tools/call only
# ever returned the JSON-serialized text block — so the schema described a
# structured result the server never sent.
#
# structuredContent (2025-06-18) and the tool title/annotations fields
# (2025-06-18 / 2025-03-26) must never reach a client on an older revision,
# which is what most of these examples assert.
RSpec.describe "MCP Streamable HTTP - structured tool output", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", "ai.loops.read", "ai.loops.execute", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:base_headers) do
    {
      "Authorization" => "Bearer #{oauth_token.plaintext_token}",
      "Content-Type" => "application/json"
    }
  end
  let(:modern_headers) { base_headers.merge("MCP-Protocol-Version" => "2025-11-25") }
  let(:legacy_headers) { base_headers.merge("MCP-Protocol-Version" => "2024-11-05") }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  def call_tool(headers:, name: "platform.list_agents")
    post mcp_endpoint,
         params: jsonrpc_request(method: "tools/call", params: { "name" => name, "arguments" => {} }),
         headers: headers
  end

  describe "tools/call structured output" do
    before do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
        .and_return({ success: true, agents: [] })
    end

    it "returns structuredContent for a 2025-11-25 client" do
      call_tool(headers: modern_headers)

      result = json_response["result"]
      expect(result["structuredContent"]).to eq({ "success" => true, "agents" => [] })
      # Unstructured content remains for backward compatibility
      expect(result["content"].first["type"]).to eq("text")
    end

    it "returns structuredContent for a 2025-06-18 client" do
      call_tool(headers: base_headers.merge("MCP-Protocol-Version" => "2025-06-18"))

      expect(json_response["result"]["structuredContent"]).to be_a(Hash)
    end

    it "wraps non-object results so structuredContent stays an object" do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_return([1, 2, 3])

      call_tool(headers: modern_headers)

      expect(json_response["result"]["structuredContent"]).to eq({ "result" => [1, 2, 3] })
    end

    it "does NOT leak structuredContent to a 2024-11-05 client" do
      call_tool(headers: legacy_headers)

      expect(json_response["result"]).not_to have_key("structuredContent")
    end

    it "does NOT leak structuredContent when the revision is unknown (spec default 2025-03-26)" do
      call_tool(headers: base_headers)

      expect(json_response["result"]).not_to have_key("structuredContent")
    end
  end

  describe "tools/list metadata by revision" do
    before do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [{ name: "list_agents", description: "List agents", parameters: {} }]
      )
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS", [])
    end

    it "includes title, outputSchema, and readOnlyHint annotations for a modern client" do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].first
      expect(tool["title"]).to eq("List Agents")
      expect(tool["outputSchema"]["type"]).to eq("object")
      expect(tool["annotations"]).to eq({ "readOnlyHint" => true })
    end

    it "returns the legacy shape (no title/outputSchema/annotations) for a 2024-11-05 client" do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: legacy_headers

      tool = json_response["result"]["tools"].first
      expect(tool.keys).to contain_exactly("name", "description", "inputSchema")
    end

    # The manifest the ActionCable catalog publishes has carried the declared
    # envelope (success / error / data with the pending approval body) since
    # IMP-e809396f9eda, but tools/list — the only schema a streamable-HTTP
    # client ever sees, and the transport real agents use — advertised a bare
    # {"type" => "object"}. A strict client could not learn from the wire that
    # a success:true response may be a PARKED action with nothing applied.
    # One source of truth: McpPlatformToolRegistrar.default_output_schema.
    it "advertises the declared result envelope, not a bare object schema" do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].first
      expect(tool["outputSchema"]).to eq(
        ::Ai::Tools::McpPlatformToolRegistrar.default_output_schema.deep_stringify_keys
      )
      expect(tool["outputSchema"]["properties"]).to include("success", "error", "data")
      expect(tool["outputSchema"]["properties"]["data"]["properties"]).to include(
        "pending", "action_category", "deferred_operation_id", "approval_request_id"
      )
      expect(tool["outputSchema"]["required"]).to eq(["success"])
    end

    # Introspection tools (platform.health, platform.metrics, ...) are served by
    # Ai::Introspection::McpToolRegistrar.execute_tool, which returns the metrics
    # / health service hash DIRECTLY — no success/error/data envelope. Handing
    # them the platform envelope would advertise `required: ["success"]` for a
    # result that never carries `success`, so a strict client would reject every
    # valid introspection response. They keep the generic object schema.
    it "does NOT give introspection tools the platform result envelope" do
      stub_const(
        "Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS",
        [{ id: "platform.health", description: "Health", input_schema: { "type" => "object" } }]
      )

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].find { |t| t["name"] == "platform.health" }
      expect(tool["outputSchema"]).to eq({ "type" => "object" })
    end

    it "does not mark non-read-only tools with readOnlyHint" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [{ name: "create_agent", description: "Create agent", parameters: {} }]
      )

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].first
      expect(tool).not_to have_key("annotations")
    end
  end
end
