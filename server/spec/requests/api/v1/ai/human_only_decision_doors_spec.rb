# frozen_string_literal: true

require "rails_helper"

# MCP identity plan R2 through the real decision doors. A human-only action
# parked by a tool call is decided only from a person's OWN session. The REST
# approval door accepts that session and refuses an impersonation one by name.
# The MCP approve and reject verbs refuse it by name whoever calls them. The
# replay runs AS the person who approved. An ordinary parked request keeps
# today's rule: a different eligible user may still decide it over MCP.
RSpec.describe "Human-only approvals: who decides, and where", type: :request do
  let(:account) { create(:account) }
  let(:perms) { [ "ai.agents.read", "ai.agents.manage", "ai.autonomy.approve" ] }
  let!(:requester) { user_with_permissions(*perms, account: account) }
  let(:confirmer) { user_with_permissions(*perms, account: account) }
  let(:sightings) { [] }

  let(:tool_class) do
    seen = sightings
    klass = Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        { name: "spec_human_door_tool", description: "human-only probe",
          parameters: { action: { type: "string", required: false } } }
      end

      declare_action "spec_human_write",
                     mutating: true, human_only: true,
                     action_category: "spec.human.door",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      define_method(:call) do |_params|
        seen << { user_id: user&.id, agent_id: agent&.id }
        success_result(ran: true)
      end
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    stub_const("SpecHumanDoorTool", klass)
  end

  before do
    Ai::InterventionPolicy.register_category!("spec.human.door")
    Ai::InterventionPolicy.create!(account: account, action_category: "spec.human.door",
                                   scope: "global", policy: "auto_approve", priority: 5, is_active: true)
    tool_class
  end

  # Parked the way an MCP client's call parks it: the owner's token, no agent.
  def park_human_only!
    tool = SpecHumanDoorTool.new(account: account, user: requester)
    tool.call_origin = "mcp_oauth"
    result = tool.execute(params: { action: "spec_human_write" })
    expect(result[:data]).to include(pending: true, requires_human_session: true)
    Ai::ApprovalRequest.find(result[:data][:approval_request_id])
  end

  def park_ordinary!
    stub_const("SpecOrdinaryExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { success: true }
    end)
    gate = Ai::AutonomyGate.evaluate(action_category: "spec.ordinary.door", executor_class: "SpecOrdinaryExecutor",
                                     params: {}, account: account, requested_by: requester)
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

  def impersonation_headers_for(user)
    admin = create(:user, :admin, account: account)
    session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
    payload = { type: "impersonation", session_id: session.id, sub: user.id, account_id: user.account_id,
                version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  it "is approved from a person's own session over REST, and runs as that person" do
    request = park_human_only!

    post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: auth_headers_for(confirmer), as: :json

    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
    expect(sightings).to eq([ { user_id: confirmer.id, agent_id: nil } ])
  end

  it "lets a solo owner confirm their own client's request from their own session, and runs as them" do
    request = park_human_only!

    post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: auth_headers_for(requester), as: :json

    expect(response).to have_http_status(:ok)
    expect(sightings).to eq([ { user_id: requester.id, agent_id: nil } ])
  end

  it "refuses an impersonation session by name, and nothing runs" do
    request = park_human_only!

    post "/api/v1/ai/autonomy/approvals/#{request.id}/approve", headers: impersonation_headers_for(confirmer),
                                                                as: :json

    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include("needs a person deciding it in their own session")
    expect(request.reload.status).to eq("pending")
    expect(sightings).to be_empty
  end

  it "is refused by name by the MCP approve and reject verbs, even for a different eligible user" do
    request = park_human_only!

    %w[approve reject].each do |verb|
      result = mcp_decide!(confirmer, verb, request)
      expect(result).to include("success" => false, "requires_human_session" => true)
      expect(result["error"]).to include("approval queue")
    end

    expect(request.reload.status).to eq("pending")
    expect(request.decisions.count).to eq(0)
    expect(sightings).to be_empty
  end

  it "leaves an ordinary request decidable over MCP by a different eligible user (the other arm)" do
    request = park_ordinary!

    result = mcp_decide!(confirmer, "approve", request)

    expect(result).to include("success" => true)
    expect(request.reload.status).to eq("approved")
  end

  it "flags the human-only request, and only it, on the approval queue read" do
    human = park_human_only!
    ordinary = park_ordinary!

    get "/api/v1/ai/autonomy/approvals", headers: auth_headers_for(confirmer)

    rows = json_response["data"].index_by { |row| row["id"] }
    expect(rows.fetch(human.id)["requires_human_session"]).to be(true)
    expect(rows.fetch(ordinary.id)["requires_human_session"]).to be(false)
  end
end
