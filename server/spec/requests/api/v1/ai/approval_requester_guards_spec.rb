# frozen_string_literal: true

require "rails_helper"

# MCP identity plan D1, guards (a) and (c), under the user's ruling on (a).
#
# A request that came through a TOOL door (it carries a call_origin, or it is a
# legacy row with an agent_id) is never decided through any tool door by the
# principal that asked for it: not the requesting agent, and not the
# requested_by user's own token over MCP. That user MAY decide it from their own
# REST/UI session, so a single-user install keeps working; an impersonation or a
# delegated session is not their own. A different eligible user may decide it
# over MCP. A request parked from a person's own REST/UI session keeps today's
# rule. Every decision records the door it came through.
RSpec.describe "Approval requester exclusion and decision origin (MCP identity plan D1)", type: :request do
  let(:account) { create(:account) }
  let(:perms) { [ "ai.agents.read", "ai.agents.manage", "ai.autonomy.approve" ] }
  let!(:owner) { user_with_permissions(*perms, account: account) }
  let(:second) { user_with_permissions(*perms, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: owner) }
  let(:sightings) { [] }

  let(:tool_class) do
    seen = sightings
    klass = Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        { name: "spec_gated_door_tool", description: "gated probe",
          parameters: { action: { type: "string", required: false } } }
      end

      # No policy row: an unmatched category resolves to require_approval, so it parks.
      declare_action "spec_gated_write",
                     mutating: true,
                     action_category: "spec.gated.door",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      define_method(:call) do |_params|
        seen << { user_id: user&.id, agent_id: agent&.id }
        success_result(ran: true)
      end
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    stub_const("SpecGatedDoorTool", klass)
  end

  before do
    Ai::InterventionPolicy.register_category!("spec.gated.door")
    tool_class
  end

  # Parked the way a person's Claude Code parks it: their OAuth token, no agent.
  def park_from_mcp!(user)
    tool = SpecGatedDoorTool.new(account: account, user: user)
    tool.call_origin = "mcp_oauth"
    park!(tool)
  end

  # Parked by an agent through the agent bridge.
  def park_from_agent!
    tool = SpecGatedDoorTool.new(account: account, user: owner, agent: agent)
    tool.call_origin = "agent_bridge"
    park!(tool)
  end

  def park!(tool)
    result = tool.execute(params: { action: "spec_gated_write" })
    expect(result[:data]).to include(pending: true)
    Ai::ApprovalRequest.find(result[:data][:approval_request_id])
  end

  # A row written before the door was marked: it names the agent, and no call_origin.
  def park_legacy_agent_row!
    park_through_gate!(agent: agent, requested_by: owner)
  end

  # Parked from a person's own REST/UI session: no mark, no agent.
  def park_from_rest!(user)
    park_through_gate!(requested_by: user)
  end

  def park_through_gate!(**who)
    stub_const("SpecPlainExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { success: true }
    end)
    gate = Ai::AutonomyGate.evaluate(action_category: "spec.gated.door", executor_class: "SpecPlainExecutor",
                                     params: {}, account: account, **who)
    expect(gate.decision).to eq(:pending)
    gate.approval_request
  end

  def mcp_headers_for(user)
    app = create(:oauth_application, :mcp_client)
    token = create(:oauth_access_token, oauth_app: app, resource_owner_id: user.id, scopes: "read write")
    { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end

  def mcp_decide!(user, verb, request)
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => "platform.#{verb}_deferred_operation",
                             "arguments" => { "deferred_operation_id" => request.id } } }.to_json,
         headers: mcp_headers_for(user)
    json_response.dig("result", "structuredContent")
  end

  def rest_approve!(request, headers)
    post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: headers, as: :json
  end

  def impersonation_headers_for(user)
    admin = create(:user, :admin, account: account)
    session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
    payload = { type: "impersonation", session_id: session.id, sub: user.id, account_id: user.account_id,
                version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  def expect_undecided(request)
    expect(request.reload.status).to eq("pending")
    expect(request.decisions.count).to eq(0)
    expect(sightings).to be_empty
  end

  it "lets a solo owner approve their own Claude Code's parked request from their own session, and it runs as them" do
    request = park_from_mcp!(owner)

    rest_approve!(request, auth_headers_for(owner))

    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
    expect(sightings).to eq([ { user_id: owner.id, agent_id: nil } ])
    expect(request.decisions.sole.origin).to eq("rest_session")
  end

  it "refuses the same owner's MCP token approving or rejecting it" do
    request = park_from_mcp!(owner)

    %w[approve reject].each do |verb|
      result = mcp_decide!(owner, verb, request)
      expect(result).to include("success" => false)
      expect(result["error"]).to include("asked for it")
    end
    expect_undecided(request)
  end

  it "refuses the requesting agent, whichever user it carries" do
    request = park_from_agent!

    [ owner, second ].each do |carried|
      tool = Ai::Tools::AgentAutonomyTool.new(account: account, user: carried, agent: agent)
      tool.call_origin = "agent_bridge"
      result = tool.execute(params: { action: "approve_deferred_operation", deferred_operation_id: request.id })
      expect(result).to include(success: false)
    end
    expect_undecided(request)

    # The same refusal one level down, at the decision itself.
    workflow = Ai::Autonomy::ApprovalWorkflowService.new(account: account)
    expect(workflow.approve(request: request, approver: second, origin: "agent_bridge", agent: agent)).to be(false)
    expect_undecided(request)
  end

  it "lets the requesting agent's user decide it from their own session" do
    request = park_from_agent!

    rest_approve!(request, auth_headers_for(owner))

    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
    expect(sightings).to eq([ { user_id: owner.id, agent_id: agent.id } ])
  end

  it "refuses the requester from a session that is not their own (impersonation), by name" do
    request = park_from_mcp!(owner)

    rest_approve!(request, impersonation_headers_for(owner))

    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include("own session")
    expect_undecided(request)
  end

  it "lets a second user approve an ordinary request over MCP, recording the MCP door" do
    request = park_from_mcp!(owner)

    result = mcp_decide!(second, "approve", request)

    expect(result).to include("success" => true)
    expect(request.reload.status).to eq("approved")
    # An ordinary request replays as the principal that asked for it.
    expect(sightings).to eq([ { user_id: owner.id, agent_id: nil } ])
    expect(request.decisions.sole).to have_attributes(approver_id: second.id, origin: "mcp_oauth")
  end

  it "lets a second user approve it from an impersonation session, and records that door" do
    request = park_from_mcp!(owner)

    rest_approve!(request, impersonation_headers_for(second))

    expect(response).to have_http_status(:ok)
    expect(request.decisions.sole).to have_attributes(approver_id: second.id, origin: "rest")
  end

  it "treats a legacy row that names an agent as a tool-door request" do
    request = park_legacy_agent_row!

    expect(mcp_decide!(owner, "approve", request)).to include("success" => false)
    expect(request.reload.status).to eq("pending")

    rest_approve!(request, auth_headers_for(owner))
    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
  end

  it "keeps today's rule for a request parked from a person's own session: its requester may decide it over MCP" do
    request = park_from_rest!(owner)

    result = mcp_decide!(owner, "approve", request)

    expect(result).to include("success" => true)
    expect(request.reload.status).to eq("approved")
    expect(request.decisions.sole.origin).to eq("mcp_oauth")
  end

  it "marks the parked request with the tool door it came through, and a REST-parked one with none" do
    expect(park_from_mcp!(owner).request_data["call_origin"]).to eq("mcp_oauth")
    expect(park_from_agent!.request_data["call_origin"]).to eq("agent_bridge")
    expect(park_from_rest!(owner).request_data).not_to have_key("call_origin")
  end

  # Guard (b) through the real doors: a request in a default category needs a person's
  # own session. A second, eligible user's MCP call is refused by name; their own REST
  # session decides it.
  context "when the request is in a category that needs a person (the default set: campaign lifecycle)" do
    before do
      Ai::InterventionPolicy.register_category!("campaign.spec_probe")
      stub_const("SpecCampaignTool", Class.new(SpecGatedDoorTool) do
        declare_action "spec_gated_write",
                       mutating: true,
                       action_category: "campaign.spec_probe",
                       executor_class: "Ai::Executors::DeferredToolCall",
                       gate_context: :deferred_tool_call_context,
                       on_proceed: :deferred_tool_call_result
      end)
    end

    it "refuses a second user's MCP decision by name, and takes their own session's" do
      tool = SpecCampaignTool.new(account: account, user: owner)
      tool.call_origin = "mcp_oauth"
      request = park!(tool)
      expect(request.requires_human_session?).to be(true)

      result = mcp_decide!(second, "approve", request)
      expect(result).to include("success" => false, "requires_human_session" => true)
      expect_undecided(request)

      rest_approve!(request, auth_headers_for(second))
      expect(response).to have_http_status(:ok)
      expect(request.reload.status).to eq("approved")
      expect(request.decisions.sole.origin).to eq("rest_session")
    end
  end
end
