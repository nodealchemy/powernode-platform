# frozen_string_literal: true

require "rails_helper"

# THE DOOR MARKS THE CALL, NEVER THE AGENT RECORD (MCP identity plan R3).
#
# An OAuth MCP call carries an mcp_client agent only when the account has an
# active AI provider to back one (Ai::McpClientIdentityService#create_mcp_agent
# returns nil otherwise). Every check that asked "is an agent set?" therefore
# read a no-provider MCP call as a person's own call. The mark the door sets
# is derived from HOW the call arrived, so both arms below carry the same one:
# with a client agent, and with none.
RSpec.describe "MCP door call_origin mark", type: :request do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}", "Content-Type" => "application/json" }
  end

  # What the controller handed the registrar, captured without changing it.
  def call_tool_capturing_registrar_kwargs
    seen = nil
    allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_wrap_original do |original, *args, **kwargs|
      seen = kwargs
      original.call(*args, **kwargs)
    end

    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => "platform.list_agents", "arguments" => {} } }.to_json,
         headers: headers
    seen
  end

  it "marks an OAuth call mcp_oauth when no client agent can be created (no active provider)" do
    account.ai_providers.update_all(is_active: false)

    seen = call_tool_capturing_registrar_kwargs

    expect(response).to have_http_status(:ok)
    expect(account.ai_agents.where(agent_type: "mcp_client")).to be_empty
    expect(seen).to include(mcp_agent: nil)
    expect(seen[:origin]).to eq("mcp_oauth")
  end

  it "marks the same origin when the call does carry a client agent (the other arm)" do
    create(:ai_provider, account: account, is_active: true) unless account.ai_providers.where(is_active: true).exists?

    seen = call_tool_capturing_registrar_kwargs

    expect(response).to have_http_status(:ok)
    expect(seen[:mcp_agent]).to be_a(Ai::Agent)
    expect(seen[:mcp_agent].agent_type).to eq("mcp_client")
    expect(seen[:origin]).to eq("mcp_oauth")
  end
end
