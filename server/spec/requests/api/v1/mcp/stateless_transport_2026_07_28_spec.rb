# frozen_string_literal: true

require "rails_helper"

# Revision 2026-07-28 removed the initialize handshake: the protocol version
# and client capabilities travel per-request in params._meta, mirrored by
# request-metadata headers, and results carry a resultType plus cache hints.
#
# Both eras share one endpoint, so the invariant that matters most here is
# containment: everything this revision adds must be absent for clients on
# 2024-11-05 .. 2025-11-25, which keep the handshake and the old result shape.
# server/discover is the deliberate exception — it is the cross-era version
# probe, so it answers whoever asks.
RSpec.describe "MCP Streamable HTTP - 2026-07-28 stateless transport", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", "ai.workflows.read", "ai.workflows.execute", account: account) }
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
  # A client on the newest STATEFUL revision (sends the standard version header)
  let(:modern_headers) { base_headers.merge("MCP-Protocol-Version" => "2025-11-25") }
  # A client that negotiated the oldest supported revision
  let(:legacy_headers) { base_headers.merge("MCP-Protocol-Version" => "2024-11-05") }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  # 2026-07-28 stateless request body: protocol version + client capabilities
  # travel in params._meta.
  def stateless_body(method:, params: {}, id: 1, version: "2026-07-28")
    meta = {
      "io.modelcontextprotocol/protocolVersion" => version,
      "io.modelcontextprotocol/clientCapabilities" => {}
    }
    { jsonrpc: "2.0", id: id, method: method, params: params.merge("_meta" => meta) }.to_json
  end

  # 2026-07-28 required request-metadata headers.
  def stateless_headers(method:, name: nil, version: "2026-07-28")
    headers = base_headers.merge("MCP-Protocol-Version" => version, "Mcp-Method" => method)
    headers["Mcp-Name"] = name if name
    headers
  end

  # ===========================================================================
  # server/discover + the 2026-07-28 stateless transport
  # ===========================================================================
  describe "server/discover" do
    it "advertises all supported protocol versions and stateless-era capabilities" do
      post mcp_endpoint, params: jsonrpc_request(method: "server/discover"), headers: base_headers

      result = json_response["result"]
      expect(result["supportedVersions"]).to eq(["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"])
      expect(result["capabilities"]["tools"]).to eq({ "listChanged" => false })
      expect(result["capabilities"]["completions"]).to eq({})
      expect(result["capabilities"]["resources"]).to eq({ "listChanged" => false })
      # DiscoverResult extends CacheableResult and Result — these fields are
      # part of its schema in every case.
      expect(result["resultType"]).to eq("complete")
      expect(result["ttlMs"]).to eq(3_600_000)
      expect(result["cacheScope"]).to eq("public")
      expect(result.dig("_meta", "io.modelcontextprotocol/serverInfo", "name")).to eq("Powernode AI Platform")
    end
  end

  # ===========================================================================
  # 2026-07-28 stateless era: per-request _meta version, request-metadata
  # headers, result envelopes
  # ===========================================================================
  describe "stateless era (2026-07-28)" do
    before do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [{ name: "list_agents", description: "List agents", parameters: {} }]
      )
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS", [])
    end

    it "serves tools/list with resultType, cache hints, and serverInfo — no session minted" do
      post mcp_endpoint,
           params: stateless_body(method: "tools/list"),
           headers: stateless_headers(method: "tools/list")

      expect(response).to have_http_status(:ok)
      expect(response.headers["MCP-Protocol-Version"]).to eq("2026-07-28")
      expect(response.headers["Mcp-Session-Id"]).to be_nil

      result = json_response["result"]
      expect(result["tools"].map { |t| t["name"] }).to eq(["platform.list_agents"])
      expect(result["resultType"]).to eq("complete")
      expect(result["ttlMs"]).to eq(300_000)
      expect(result["cacheScope"]).to eq("private")
      expect(result.dig("_meta", "io.modelcontextprotocol/serverInfo", "name")).to eq("Powernode AI Platform")
    end

    it "serves tools/call with structuredContent and resultType but no cache hints" do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
        .and_return({ success: true, agents: [] })

      post mcp_endpoint,
           params: stateless_body(method: "tools/call",
                                  params: { "name" => "platform.list_agents", "arguments" => {} }),
           headers: stateless_headers(method: "tools/call", name: "platform.list_agents")

      result = json_response["result"]
      expect(result["resultType"]).to eq("complete")
      expect(result["structuredContent"]).to eq({ "success" => true, "agents" => [] })
      expect(result).not_to have_key("ttlMs")
    end

    it "accepts a Base64-sentinel Mcp-Name header" do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_return({ success: true })
      encoded = "=?base64?#{Base64.strict_encode64('platform.list_agents')}?="

      post mcp_endpoint,
           params: stateless_body(method: "tools/call",
                                  params: { "name" => "platform.list_agents", "arguments" => {} }),
           headers: stateless_headers(method: "tools/call", name: encoded)

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]["resultType"]).to eq("complete")
    end

    it "rejects tools/call missing the Mcp-Name header with 400 / -32020" do
      post mcp_endpoint,
           params: stateless_body(method: "tools/call",
                                  params: { "name" => "platform.list_agents", "arguments" => {} }),
           headers: stateless_headers(method: "tools/call")

      expect(response).to have_http_status(:bad_request)
      expect(json_response["error"]["code"]).to eq(-32020)
    end

    it "rejects an Mcp-Method header that does not match the body with 400 / -32020" do
      post mcp_endpoint,
           params: stateless_body(method: "tools/list"),
           headers: stateless_headers(method: "prompts/list")

      expect(response).to have_http_status(:bad_request)
      expect(json_response["error"]["code"]).to eq(-32020)
      expect(json_response["error"]["message"]).to include("Mcp-Method")
    end

    it "rejects a version header that does not match _meta with 400 / -32020" do
      post mcp_endpoint,
           params: stateless_body(method: "tools/list"),
           headers: stateless_headers(method: "tools/list", version: "2025-11-25")
             .merge("MCP-Protocol-Version" => "2025-11-25")

      # body _meta says 2026-07-28, header says 2025-11-25
      expect(response).to have_http_status(:bad_request)
      expect(json_response["error"]["code"]).to eq(-32020)
      expect(json_response["error"]["message"]).to include("MCP-Protocol-Version")
    end

    it "rejects an unsupported protocol version with 400 / -32022 listing supported versions" do
      post mcp_endpoint,
           params: stateless_body(method: "tools/list", version: "2027-01-01"),
           headers: stateless_headers(method: "tools/list", version: "2027-01-01")

      expect(response).to have_http_status(:bad_request)
      error = json_response["error"]
      expect(error["code"]).to eq(-32022)
      expect(error["data"]["requested"]).to eq("2027-01-01")
      expect(error["data"]["supported"]).to include("2026-07-28", "2025-11-25")
    end

    it "returns 404 / -32601 for an unknown method (stateful era keeps 200)" do
      post mcp_endpoint,
           params: stateless_body(method: "bogus/method"),
           headers: stateless_headers(method: "bogus/method")

      expect(response).to have_http_status(:not_found)
      expect(json_response["error"]["code"]).to eq(-32601)
    end

    it "leaves stateful-era responses untouched (no resultType/ttlMs/_meta injection)" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: modern_headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]).to eq({})
      expect(response.headers["MCP-Protocol-Version"]).to eq("2025-11-25")
    end
  end

  # ===========================================================================
  # JSON-RPC conformance: nested handler errors carry the request id
  # ===========================================================================
end
