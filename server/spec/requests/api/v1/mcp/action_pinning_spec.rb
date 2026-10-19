# frozen_string_literal: true

require "rails_helper"

# C13 — a Claude Code session (an OAuth MCP client) is held to the action its
# invoked tool name names. The C4 thin loaders deny destroy-shaped verbs to the
# granted subagents by exact tool name (disallowedTools); before this, the same
# session reached a denied verb through any sibling tool of its class by
# supplying `action:` (platform.list_agents carrying action "delete_agent").
RSpec.describe "MCP streamable HTTP pins the action to the tool name", type: :request do
  let(:account) { create(:account) }
  let!(:user) do
    create(:user, account: account, permissions: %w[ai.agents.read ai.agents.execute ai.agents.delete])
  end
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}", "Content-Type" => "application/json" }
  end
  let!(:target) { create(:ai_agent, account: account) }

  def call_tool(name, arguments)
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => name, "arguments" => arguments } }.to_json,
         headers: headers
    JSON.parse(response.body)
  end

  it "refuses delete_agent smuggled through platform.list_agents, and the agent survives" do
    body = call_tool("platform.list_agents", { "action" => "delete_agent", "agent_id" => target.id })

    expect(body["error"]).to be_present
    expect(body.dig("error", "message")).to match(/delete_agent/)
    expect(Ai::Agent.exists?(target.id)).to be(true)
  end

  it "still serves the invoked name when the client supplies no action" do
    body = call_tool("platform.list_agents", {})

    expect(body["error"]).to be_nil
    expect(body["result"]).to be_present
    expect(Ai::Agent.exists?(target.id)).to be(true)
  end
end
