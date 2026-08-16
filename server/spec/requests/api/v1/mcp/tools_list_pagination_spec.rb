# frozen_string_literal: true

require "rails_helper"

# tools/list has accepted a `cursor` and returned `nextCursor` since the very
# first protocol revision, but this server ignored both and always returned the
# entire catalog. Deterministic ordering is what makes an offset cursor sound:
# registry hash order is not stable across processes, so page 2 of an unsorted
# list could skip or repeat tools.
RSpec.describe "MCP Streamable HTTP - tools/list pagination", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", "ai.workflows.read", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    {
      "Authorization" => "Bearer #{oauth_token.plaintext_token}",
      "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25"
    }
  end
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  let(:many_tools) do
    (1..260).map do |i|
      { name: format("bulk_tool_%03d", i), description: "Bulk tool #{i}", parameters: {} }
    end
  end

  before do
    allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(many_tools)
    stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS", [])
    # Pin the bound this file's expectations are written against, rather than
    # inheriting whatever TOOLS_PAGE_SIZE currently is. The subject here is the
    # pagination MECHANISM — cap, nextCursor, resume, final page — not the
    # production page size, and the two must be able to move independently.
    #
    # Previously this spec relied on the real constant being 250 and on the
    # stubbed catalog (260) exceeding it. That coupling made it fail the moment
    # TOOLS_PAGE_SIZE was raised to stop the production catalog (611) being
    # silently truncated — i.e. the spec went red for a fix, not a regression.
    # Whether the production bound is big enough is a different question, and it
    # has its own guard: tools_list_page_size_spec.rb.
    stub_const("Api::V1::Mcp::StreamableHttpController::TOOLS_PAGE_SIZE", 250)
  end

  it "caps the first page and returns nextCursor" do
    post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

    result = json_response["result"]
    expect(result["tools"].size).to eq(250)
    expect(result["nextCursor"]).to eq("250")
  end

  it "resumes from the cursor and omits nextCursor on the final page" do
    post mcp_endpoint,
         params: jsonrpc_request(method: "tools/list", params: { "cursor" => "250" }),
         headers: headers

    result = json_response["result"]
    expect(result["tools"].size).to eq(10)
    expect(result["tools"].first["name"]).to eq("platform.bulk_tool_251")
    expect(result).not_to have_key("nextCursor")
  end

  it "returns -32602 for an invalid cursor" do
    post mcp_endpoint,
         params: jsonrpc_request(method: "tools/list", params: { "cursor" => "not-a-cursor" }),
         headers: headers

    expect(json_response["error"]["code"]).to eq(-32602)
    expect(json_response["error"]["message"]).to include("cursor")
  end

  # The page size is deliberately above the live catalog size, so today's
  # clients — including grant-scoped instance principals — keep receiving the
  # whole catalog in one response with no cursor to follow.
  it "returns the full catalog with no nextCursor when it fits in one page" do
    allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(many_tools.first(3))

    post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

    result = json_response["result"]
    expect(result["tools"].size).to eq(3)
    expect(result).not_to have_key("nextCursor")
  end

  it "returns tools in deterministic (name-sorted) order" do
    allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
      [
        { name: "zeta_tool", description: "Z", parameters: {} },
        { name: "alpha_tool", description: "A", parameters: {} }
      ]
    )

    post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

    names = json_response["result"]["tools"].map { |t| t["name"] }
    expect(names).to eq(["platform.alpha_tool", "platform.zeta_tool"])
  end
end
