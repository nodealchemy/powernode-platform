# frozen_string_literal: true

require "rails_helper"

# Cross-plane MCP: a peer Powernode deployment authenticates to this plane's MCP
# endpoint with its shared federation bearer token + X-Federation-Organization
# header, and is mapped to a DEFAULT-DENY federation principal scoped to the
# partner's allowed_capabilities. Additive to the OAuth and mTLS paths.
RSpec.describe "MCP federation authentication", type: :request do
  let(:account) { create(:account, status: "active") }
  let(:allowed) { [ "platform.read_shared_memory" ] }
  let(:partner) do
    # factory sets federation_token_hash = bcrypt("test_token")
    create(:federation_partner, :active, account: account, allowed_capabilities: allowed)
  end

  def post_rpc(method:, params: {}, headers: {})
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
  end

  def fed_headers(org: partner.organization_id, token: "test_token")
    { "X-Federation-Organization" => org, "Authorization" => "Bearer #{token}" }
  end

  it "authenticates a valid partner and scopes tools/list to allowed_capabilities" do
    post_rpc(method: "tools/list", headers: fed_headers)
    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body).dig("result", "tools").map { |t| t["name"] }
    expect(names).to include("platform.read_shared_memory")
    expect(names).not_to include("platform.system_destroy_instance")
  end

  it "rejects a bad token with 401" do
    post_rpc(method: "tools/list", headers: fed_headers(token: "wrong"))
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a federation header with no bearer token" do
    post_rpc(method: "tools/list", headers: { "X-Federation-Organization" => partner.organization_id })
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a suspended partner" do
    partner.update!(status: "suspended")
    post_rpc(method: "tools/list", headers: fed_headers)
    expect(response).to have_http_status(:unauthorized)
  end

  it "runs a granted, non-destructive tool via tools/call" do
    executed = []
    allow_any_instance_of(Ai::Tools::MemoryTool).to receive(:execute) do |_tool, params:|
      executed << params[:action]
      { success: true }
    end

    post_rpc(method: "tools/call",
             params: { name: "platform.read_shared_memory", arguments: { pool_id: "default", key: "k" } },
             headers: fed_headers)

    expect(executed).to eq([ "read_shared_memory" ])
  end

  it "denies an ungranted tool via tools/call" do
    post_rpc(method: "tools/call", params: { name: "platform.kb_publish", arguments: {} }, headers: fed_headers)
    expect(response.body).to include("not permitted")
  end

  it "denies a destroy-shaped tool even when allowed_capabilities would match" do
    partner.update!(allowed_capabilities: [ "platform.system_*" ])
    post_rpc(method: "tools/call",
             params: { name: "platform.system_terminate_instance", arguments: {} },
             headers: fed_headers)
    expect(response.body).to include("not permitted")
  end

  it "denies resources/read to a federation principal (tool-only surface)" do
    post_rpc(method: "resources/read", params: { uri: "powernode://ai/agents/x" }, headers: fed_headers)
    expect(JSON.parse(response.body).dig("error", "message")).to match(/not available to this principal/)
  end

  it "leaves the OAuth path untouched when no federation header is present" do
    post_rpc(method: "tools/list", headers: {})
    expect(response).to have_http_status(:unauthorized)
  end

  # --- Security remediation (adversarial review F1/F3) ---

  it "denies session/discover to a federation principal (session-enumeration vector)" do
    post_rpc(method: "session/discover", headers: fed_headers)
    expect(JSON.parse(response.body).dig("error", "message")).to match(/not available to this principal/)
  end

  it "cannot revoke another principal's session by presenting its token" do
    victim_user = create(:user, account: account)
    victim = McpSession.create!(
      account: account, user: victim_user,
      session_token: "victim-#{SecureRandom.hex(6)}", status: "active", expires_at: 1.hour.from_now
    )

    delete "/api/v1/mcp/message",
           headers: { "Accept" => "application/json", "Mcp-Session-Id" => victim.session_token }.merge(fed_headers)

    expect(victim.reload.status).to eq("active")
  end

  it "throttles repeated failed federation auth to bound bcrypt work" do
    stub_const("McpTokenAuthentication::FEDERATION_AUTH_FAILURE_LIMIT", 2)

    2.times do
      post_rpc(method: "tools/list", headers: fed_headers(token: "wrong"))
      expect(JSON.parse(response.body)["error_code"]).to eq("federation_invalid")
    end

    post_rpc(method: "tools/list", headers: fed_headers(token: "wrong"))
    expect(JSON.parse(response.body)["error_code"]).to eq("federation_throttled")
  end
end
