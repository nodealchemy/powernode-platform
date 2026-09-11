# frozen_string_literal: true

require "rails_helper"

# MCP identity plan #7, through the real door. DataSourceTool#permission? used to
# answer "allowed" for any call without an agent, on the premise that a REST
# controller had already authorized it. An OAuth MCP call in an account with no
# active AI provider carries no client agent, so a user holding only
# ai.data_sources.read could update a data source. A call the door marked is now
# checked against its own user's grant.
RSpec.describe "Data-source mutations over OAuth MCP check the caller's own grant (MCP identity plan #7)",
               type: :request do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) } # first user: OWNER, holds every permission
  let!(:data_source) do
    create(:ai_data_source, account: account, slug: "open-meteo", source_type: "open_meteo", name: "Before")
  end

  # No client agent can be created: the call reaches the tool with no agent.
  before { account.ai_providers.update_all(is_active: false) }

  def headers_for(user)
    app = create(:oauth_application, :mcp_client)
    token = create(:oauth_access_token, oauth_app: app, resource_owner_id: user.id, scopes: "read write")
    { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end

  def mcp_update(user)
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => "platform.data_source_update",
                             "arguments" => { "data_source_id" => data_source.id, "name" => "After" } } }.to_json,
         headers: headers_for(user)
    json_response.dig("result", "structuredContent")
  end

  it "refuses a user holding only ai.data_sources.read, though the account's owner holds the grant" do
    reader = user_with_permissions("ai.data_sources.read", account: account)

    result = mcp_update(reader)

    expect(result).to include("success" => false)
    expect(result["error"]).to include("ai.data_sources.update")
    expect(data_source.reload.name).to eq("Before")
    expect(account.ai_agents.where(agent_type: "mcp_client")).to be_empty
  end

  it "lets a user holding ai.data_sources.update through (the control)" do
    updater = user_with_permissions("ai.data_sources.read", "ai.data_sources.update", account: account)

    result = mcp_update(updater)

    expect(result).to include("success" => true)
    expect(data_source.reload.name).to eq("After")
  end
end
