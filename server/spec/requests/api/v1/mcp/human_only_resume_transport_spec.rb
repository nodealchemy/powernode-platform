# frozen_string_literal: true

require "rails_helper"

# secreview E12, the MCP identity plan's primary red arm, tracked. Through the
# REAL streamable door, with a Doorkeeper token for the account owner (who
# holds ai.campaigns.manage), tools/call platform.campaign_resume on a
# campaign that a stop condition auto-completed.
#
# At 76dbe6126 an account with no active AI provider got no client agent, and
# the owner's MCP call resumed the campaign as though a person had decided.
# Now the call PARKS on every arm, with a client agent or without one: the
# campaign stays completed, and no decision row is written. Only a person's
# own session confirms it, and it then runs AS that person.
RSpec.describe "campaign_resume over OAuth MCP parks for a person (E12)", type: :request do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) } # first user: OWNER, holds ai.campaigns.manage
  let(:second) do
    user_with_permissions("ai.campaigns.manage", "ai.autonomy.approve", "ai.agents.read", account: account)
  end
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}", "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end

  def auto_completed
    tool = Ai::Tools::CampaignTool.new(account: account, user: user)
    run = ->(p) { tool.execute(params: p.with_indifferent_access) }
    id = run.call(action: "campaign_start", name: "Mcp-#{SecureRandom.hex(3)}",
                  stop_conditions: { max_failed: 2 })[:data][:campaign][:id]
    2.times { |i| run.call(action: "campaign_record_increment", campaign_id: id, title: "broken #{i}", status: "failed") }
    campaign = account.ai_campaigns.find(id)
    raise "precondition: not auto-completed (#{campaign.status})" unless campaign.status == "completed"

    campaign
  end

  def mcp_call(name, arguments)
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => name, "arguments" => arguments } }.to_json,
         headers: headers
    json_response.dig("result", "structuredContent")
  end

  def mcp_resume(campaign)
    mcp_call("platform.campaign_resume",
             "campaign_id" => campaign.id, "reason" => "over mcp", "stop_conditions" => { "max_failed" => 6 })
  end

  def resume_decisions(campaign) = campaign.campaign_decisions.where("metadata->>'action' = ?", "campaign_resume")

  # Both arms of the transport: the verdict must not depend on the client agent.
  def expect_parked(campaign, result)
    expect(response).to have_http_status(:ok)
    expect(result).to include("success" => true)
    expect(result["data"]).to include("pending" => true, "requires_human_session" => true)
    expect(result["data"]["message"]).to include("approval queue")
    expect(campaign.reload.status).to eq("completed")
    expect(campaign.stop_conditions["max_failed"]).to eq(2)
    expect(resume_decisions(campaign)).to be_empty

    request = Ai::ApprovalRequest.find(result["data"]["approval_request_id"])
    expect(request.requires_human_session?).to be(true)
    expect(request.description).to eq("Resume campaign \"#{campaign.name}\": max_failed 2 -> 6")
    request
  end

  context "when the account has no active AI provider (no client agent can be created)" do
    before { account.ai_providers.update_all(is_active: false) }

    it "parks, and a different person's own session runs it as that person" do
      campaign = auto_completed
      request = expect_parked(campaign, mcp_resume(campaign))
      expect(account.ai_agents.where(agent_type: "mcp_client")).to be_empty

      post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: auth_headers_for(second), as: :json

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq("active")
      expect(campaign.stop_conditions["max_failed"]).to eq(6)
      expect(resume_decisions(campaign).sole.user_id).to eq(second.id)
    end

    it "lets the solo owner confirm their own client's request from their own session, and runs as them" do
      campaign = auto_completed
      request = expect_parked(campaign, mcp_resume(campaign))

      post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq("active")
      expect(resume_decisions(campaign).sole.user_id).to eq(user.id)
    end

    it "refuses the owner's own MCP token deciding it, by name" do
      campaign = auto_completed
      request = expect_parked(campaign, mcp_resume(campaign))

      result = mcp_call("platform.approve_deferred_operation", "deferred_operation_id" => request.id)

      expect(result).to include("success" => false, "requires_human_session" => true)
      expect(request.reload.status).to eq("pending")
      expect(campaign.reload.status).to eq("completed")
    end
  end

  context "when the account has an active AI provider (the call carries a client agent)" do
    before do
      create(:ai_provider, account: account, is_active: true) unless account.ai_providers.where(is_active: true).exists?
    end

    it "parks the same way" do
      campaign = auto_completed
      expect_parked(campaign, mcp_resume(campaign))
      expect(account.ai_agents.where(agent_type: "mcp_client").count).to eq(1)
    end
  end
end
