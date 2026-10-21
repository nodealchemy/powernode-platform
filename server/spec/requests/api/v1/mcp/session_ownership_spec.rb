# frozen_string_literal: true

require "rails_helper"

# An Mcp-Session-Id is a bearer of nothing on its own: a session is resolved
# from the header only for the principal that owns it (the rule
# find_mcp_session already applies to the SSE stream). Before this, the
# per-request helpers — current_mcp_session (which mcp_client_agent prefers)
# and track_session_activity — looked the session up by token alone, so a
# DIFFERENT token holder presenting a borrowed session id acted as that
# session's agent and kept that session alive.
RSpec.describe "MCP session ownership on the per-request path", type: :request do
  let(:account) { create(:account) }
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:user_a) { user_with_permissions("ai.agents.read", account: account) }
  let(:user_b) { user_with_permissions("ai.agents.read", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:token_a) { create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user_a.id, scopes: "read write") }
  let(:token_b) { create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user_b.id, scopes: "read write") }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def headers_for(token, session_id: nil)
    { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/json" }
      .merge(session_id ? { "Mcp-Session-Id" => session_id } : {})
  end

  def rpc(method, params = {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  def initialize_as(token)
    post mcp_endpoint,
         params: rpc("initialize", { "protocolVersion" => "2025-11-25",
                                     "clientInfo" => { "name" => "headersHelper", "version" => "1" } }),
         headers: headers_for(token)
    McpSession.find_by!(session_token: response.headers["Mcp-Session-Id"])
  end

  # The agent a tools/call runs as: what the controller hands the registrar.
  def call_tool_as(token, session_id)
    seen = nil
    allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_wrap_original do |original, *args, **kwargs|
      seen = kwargs[:mcp_agent]
      original.call(*args, **kwargs)
    end
    post mcp_endpoint, params: rpc("tools/call", { "name" => "platform.list_agents", "arguments" => {} }),
                       headers: headers_for(token, session_id: session_id)
    seen
  end

  it "does not let token B act as A's agent by presenting A's session id" do
    session_a = initialize_as(token_a)
    agent_a = session_a.reload.ai_agent
    expect(agent_a).to be_present

    agent = call_tool_as(token_b, session_a.session_token)

    expect(response).to have_http_status(:ok)
    expect(agent).to be_present
    expect(agent.id).not_to eq(agent_a.id)
  end

  it "does not touch A's session activity on B's request" do
    session_a = initialize_as(token_a)
    session_a.update_columns(last_activity_at: 2.hours.ago)
    before = session_a.reload.last_activity_at

    post mcp_endpoint, params: rpc("ping"), headers: headers_for(token_b, session_id: session_a.session_token)

    expect(session_a.reload.last_activity_at).to be_within(1.second).of(before)
  end

  it "does not reactivate A's revoked session for B" do
    session_a = initialize_as(token_a)
    session_a.update_columns(status: "revoked", revoked_at: 10.seconds.ago)
    status_before = session_a.reload.status

    post mcp_endpoint, params: rpc("ping"), headers: headers_for(token_b, session_id: session_a.session_token)

    expect(session_a.reload.status).to eq(status_before)
  end

  it "still resolves the owner's own session for A (control)" do
    session_a = initialize_as(token_a)
    session_a.update_columns(last_activity_at: 2.hours.ago)
    agent_a = session_a.reload.ai_agent

    expect(call_tool_as(token_a, session_a.session_token)&.id).to eq(agent_a.id)
    expect(session_a.reload.last_activity_at).to be > 1.minute.ago
  end
end
