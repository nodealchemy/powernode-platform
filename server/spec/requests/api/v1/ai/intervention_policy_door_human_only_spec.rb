# frozen_string_literal: true

require "rails_helper"

# secreview §21 G4, self-unmark. Which requests need a person's own session is
# DB-driven (Ai::Approvals::HumanSessionPolicy reads intervention-policy rows),
# and the tool doors that write those rows were gated only by
# ai.intervention_policies.manage. One MCP call writing a "*" row with
# requires_human_session false un-marked every category, and a second user's
# MCP token then approved a *decommission* request. Under the user's rule (MCP
# requests, a person confirms) the three writers are human-only: through any
# tool door they park, and a person confirms them in their own session, where
# they run as that person. The REST/UI door stays direct for a person.
RSpec.describe "Intervention-policy writes through a tool door are human-only (secreview §21 G4)", type: :request do
  let(:account) { create(:account) }
  let(:perms) { %w[ai.agents.read ai.agents.manage ai.autonomy.approve ai.intervention_policies.manage] }
  let!(:author) { user_with_permissions(*perms, account: account) }
  let(:second) { user_with_permissions(*perms, account: account) }

  let(:unmark_everything) do
    { "scope" => "global", "action_category" => "*", "policy" => "require_approval",
      "conditions" => { "requires_human_session" => false }, "priority" => 100 }
  end

  before { Ai::InterventionPolicy.register_category!("spec.node_decommission") }

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

  # A request the code-default *decommission* pattern marks human-session.
  def park_decommission!
    stub_const("SpecDecommissionExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { success: true }
    end)
    gate = Ai::AutonomyGate.evaluate(action_category: "spec.node_decommission",
                                     executor_class: "SpecDecommissionExecutor",
                                     params: {}, account: account, requested_by: author)
    expect(gate.decision).to eq(:pending)
    gate.approval_request
  end

  def expect_parked_for_a_person(result)
    expect(result).to include("success" => true)
    expect(result["data"]).to include("pending" => true, "requires_human_session" => true)
  end

  it "parks the exploit's MCP create, so the category stays marked and a second user's MCP still cannot approve" do
    request = park_decommission!
    expect(request.requires_human_session?).to be(true)

    result = nil
    expect { result = mcp_call!(author, "platform.create_intervention_policy", unmark_everything) }
      .not_to change(Ai::InterventionPolicy, :count)

    expect_parked_for_a_person(result)
    expect(request.reload.requires_human_session?).to be(true)

    decided = mcp_call!(second, "platform.approve_deferred_operation", "deferred_operation_id" => request.id)
    expect(decided).to include("success" => false)
    expect(request.reload.status).to eq("pending")
  end

  it "parks an MCP update or delete of a marking row, and the row stays as it was" do
    marking = Ai::InterventionPolicy.create!(account: account, scope: "global",
                                             action_category: "spec.node_decommission", policy: "require_approval",
                                             conditions: { "requires_human_session" => true }, priority: 5,
                                             is_active: true)

    expect_parked_for_a_person(
      mcp_call!(author, "platform.update_intervention_policy",
                "policy_id" => marking.id, "conditions" => { "requires_human_session" => false })
    )
    expect_parked_for_a_person(mcp_call!(author, "platform.delete_intervention_policy", "policy_id" => marking.id))

    expect(marking.reload.conditions).to include("requires_human_session" => true)
  end

  # The other arm, and the proof the red above is not vacuous: the same row,
  # written by a person in their own session, is written directly and does
  # un-mark the category.
  it "lets a person write the same row from their own session, directly" do
    request = park_decommission!

    post "/api/v1/ai/intervention_policies", params: unmark_everything, headers: auth_headers_for(author), as: :json

    expect(response).to have_http_status(:created)
    row = Ai::InterventionPolicy.find_by!(account_id: account.id, action_category: "*", priority: 100)
    expect(row.conditions).to include("requires_human_session" => false)
    expect(request.reload.requires_human_session?).to be(false)
  end

  it "runs a parked MCP write as the person who confirms it in their own session" do
    result = mcp_call!(author, "platform.create_intervention_policy",
                       unmark_everything.merge("action_category" => "spec.node_decommission"))
    expect_parked_for_a_person(result)

    post "/api/v1/ai/autonomy/approvals/#{result.dig('data', 'approval_request_id')}/approve",
         headers: auth_headers_for(second), as: :json

    expect(response).to have_http_status(:ok)
    row = Ai::InterventionPolicy.find_by!(account_id: account.id, action_category: "spec.node_decommission")
    expect(row.user_id).to eq(second.id)
  end
end
