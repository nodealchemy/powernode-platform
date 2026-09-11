# frozen_string_literal: true

require "rails_helper"

# The remediation front door mints its approval request itself
# (Platform::Remediation::ApprovalRequestService, through the chain
# primitives), not through Ai::AutonomyGate. So the approval guards (MCP
# identity plan D1) hold on it only if it records the door the call came
# through, as the gate does. Proved through the real MCP door: the request
# parks carrying that door, its requester's own MCP token cannot decide it,
# and a second user (or the requester, in their own session) can.
RSpec.describe "Approval guards on the remediation front door (MCP identity plan D1)", type: :request do
  let(:account) { create(:account) }
  let(:perms) do
    %w[platform.status.read ai.autonomy.manage ai.autonomy.approve ai.agents.read ai.agents.manage]
  end
  let!(:requester) { user_with_permissions(*perms, account: account) }
  let(:second) { user_with_permissions(*perms, account: account) }
  let!(:component) do
    create(:platform_component_status, account: account,
                                       component_kind: "node_instance", component_ref: "inst-guard",
                                       display_name: "Instance Guard", verdict: Platform::ComponentStatus::DOWN)
  end

  def mcp_headers_for(user)
    app = create(:oauth_application, :mcp_client)
    token = create(:oauth_access_token, oauth_app: app, resource_owner_id: user.id, scopes: "read write")
    { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end

  def mcp_call!(user, name, arguments)
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => name, "arguments" => arguments } }.to_json,
         headers: mcp_headers_for(user)
    json_response.dig("result", "structuredContent")
  end

  def park_over_mcp!(user)
    result = mcp_call!(user, "platform.request_approval",
                       "component_kind" => "node_instance", "component_ref" => "inst-guard",
                       "signal_kind" => "instance.silent", "rationale" => "silent for 20 minutes")
    expect(result).to include("success" => true)
    Ai::ApprovalRequest.find(result.dig("data", "approval_request_id"))
  end

  def expect_undecided(request)
    expect(request.reload.status).to eq("pending")
    expect(request.decisions.count).to eq(0)
  end

  it "parks the request carrying the MCP door it came through" do
    request = park_over_mcp!(requester)

    expect(request.status).to eq("pending")
    expect(request.requested_by_id).to eq(requester.id)
    expect(request.request_data["call_origin"]).to eq("mcp_oauth")
    expect(request.tool_door_request?).to be(true)
  end

  it "refuses the requester's own MCP token approving or rejecting it" do
    request = park_over_mcp!(requester)

    %w[approve reject].each do |verb|
      result = mcp_call!(requester, "platform.#{verb}_deferred_operation", "deferred_operation_id" => request.id)
      expect(result).to include("success" => false)
      expect(result["error"]).to include("asked for it")
    end
    expect_undecided(request)
  end

  it "lets a second user approve it over MCP, recording that door" do
    request = park_over_mcp!(requester)

    result = mcp_call!(second, "platform.approve_deferred_operation", "deferred_operation_id" => request.id)

    expect(result).to include("success" => true)
    expect(request.reload.status).to eq("approved")
    expect(request.decisions.sole).to have_attributes(approver_id: second.id, origin: "mcp_oauth")
  end

  it "lets the requester decide it from their own session" do
    request = park_over_mcp!(requester)

    post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: auth_headers_for(requester), as: :json

    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
    expect(request.decisions.sole.origin).to eq("rest_session")
  end
end
