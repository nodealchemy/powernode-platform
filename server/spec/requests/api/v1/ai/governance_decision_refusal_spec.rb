# frozen_string_literal: true

require "rails_helper"

# secreview §21. The governance door decides approval requests too, and it
# answered every refusal with a bare "Cannot approve". It now names the reason
# the approval queue names: a decision that needs a person's own session, a
# tool-door request decided by the person who asked for it from a session
# that is not their own, and a completing approval by someone without the
# permission the action runs under (L9).
RSpec.describe "The governance door names why it refuses a decision (secreview §21)", type: :request do
  let(:account) { create(:account) }
  let(:perms) { %w[ai.agents.read ai.agents.manage ai.autonomy.approve ai.governance.read ai.governance.manage] }
  let!(:owner) { user_with_permissions(*perms, account: account) }
  let(:second) { user_with_permissions(*perms, account: account) }
  let(:bystander) { user_with_permissions("ai.autonomy.approve", "ai.governance.read", "ai.governance.manage", account: account) }

  def probe_tool(name, human_only:)
    klass = Class.new(::Ai::Tools::BaseTool) do
      define_singleton_method(:definition) do
        { name: name, description: "governance door probe", parameters: { action: { type: "string", required: false } } }
      end

      declare_action "spec_governance_write",
                     mutating: true, human_only: human_only,
                     action_category: "spec.governance.door",
                     executor_class: "Ai::Executors::DeferredToolCall",
                     gate_context: :deferred_tool_call_context,
                     on_proceed: :deferred_tool_call_result

      define_method(:call) { |_params| success_result(ran: true) }
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    klass
  end

  before { Ai::InterventionPolicy.register_category!("spec.governance.door") }

  # Parked the way a person's Claude Code parks it: their OAuth token, no agent.
  def park_from_mcp!(user, human_only: false)
    stub_const(human_only ? "SpecGovernanceHumanTool" : "SpecGovernanceTool",
               probe_tool(human_only ? "spec_governance_human_tool" : "spec_governance_tool", human_only: human_only))
    tool = (human_only ? SpecGovernanceHumanTool : SpecGovernanceTool).new(account: account, user: user)
    tool.call_origin = "mcp_oauth"
    result = tool.execute(params: { action: "spec_governance_write" })
    expect(result[:data]).to include(pending: true)
    Ai::ApprovalRequest.find(result[:data][:approval_request_id])
  end

  def impersonation_headers_for(user)
    admin = create(:user, :admin, account: account)
    session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
    payload = { type: "impersonation", session_id: session.id, sub: user.id, account_id: user.account_id,
                version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  def decide!(request, headers, decision: "approved")
    post "/api/v1/ai/governance/approval_requests/#{request.id}/decide",
         params: { decision: decision }, headers: headers, as: :json
  end

  def expect_undecided(request)
    expect(request.reload.status).to eq("pending")
    expect(request.decisions.count).to eq(0)
  end

  it "names the own-session rule when the requester decides their tool-door request from another session" do
    request = park_from_mcp!(owner)

    decide!(request, impersonation_headers_for(owner))

    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include("you asked for it through a tool", "own session")
    expect_undecided(request)
  end

  it "names the own-session rule for a request that needs a person, decided from another session" do
    request = park_from_mcp!(owner, human_only: true)

    decide!(request, impersonation_headers_for(second), decision: "rejected")

    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include("Cannot reject this request", "own session")
    expect_undecided(request)
  end

  it "names the decider who lacks the action's permission (L9)" do
    request = park_from_mcp!(owner, human_only: true)

    decide!(request, auth_headers_for(bystander))

    expect(response).to have_http_status(:forbidden)
    expect(json_response["error"]).to include(bystander.email, "ai.agents.manage")
    expect_undecided(request)
  end

  it "decides it for a second user in their own session (the other arm)" do
    request = park_from_mcp!(owner)

    decide!(request, auth_headers_for(second))

    expect(response).to have_http_status(:ok)
    expect(request.reload.status).to eq("approved")
  end
end
