# frozen_string_literal: true

require "rails_helper"

# Act-on-behalf, the deciding half. A protected change an INSTANCE parked is
# decided by a person in their own REST session (the existing human-only door),
# and the write then runs AS that person. No second factor is asked of them.
RSpec.describe "Machine-requested protected changes: who decides", type: :request do
  let(:account) { create(:account) }
  let(:perms) { [ "ai.agents.read", "admin.access", "ai.autonomy.approve" ] }
  let!(:operator) { user_with_permissions(*perms, account: account) }
  let(:node_instance) { double("NodeInstance", id: "dd11ee22-0000-4000-8000-000000000004", account: account) }
  let(:key_a) { "zz_machine_decide_key_a" }

  before do
    Ai::Tools::SiteSettingTool.register_key(key_a, setting_type: "string", description: "decision spec", protected: true)
    ::Mcp::Principal.instance_resolver = ->(cn) { cn == node_instance.id ? node_instance : nil }
    ::Mcp::Principal.tool_grant_resolver = ->(_instance) { [ "platform.site_setting_set_protected" ] }
  end

  after { ::Mcp::Principal.reset! }

  def park_as_instance!(key, value: "armed")
    tool = Ai::Tools::SiteSettingTool.new(account: account)
    tool.instance_authorized = true
    tool.node_instance = node_instance
    tool.call_origin = "mcp_instance"
    result = tool.execute(params: { action: "site_setting_set_protected", key: key, value: value })
    expect(result[:data]).to include(pending: true)
    Ai::ApprovalRequest.find(result[:data][:approval_request_id])
  end

  def decide(verb, request, user: operator)
    post "/api/v1/ai/autonomy/approvals/#{request.id}/#{verb}", params: {}.to_json, headers: auth_headers_for(user)
  end

  def impersonation_headers_for(user)
    admin = create(:user, :admin, account: account)
    session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
    payload = { type: "impersonation", session_id: session.id, sub: user.id, account_id: user.account_id,
                version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  it "is approved from a person's own session, and the write runs AS that person" do
    request = park_as_instance!(key_a, value: "armed")
    expect(request.machine_requested?).to be(true)

    decide("approve", request)

    expect(response).to have_http_status(:ok), response.body
    expect(request.reload).to be_approved
    expect(request.decisions.last).to have_attributes(approver_id: operator.id, origin: "rest_session")
    expect(SiteSetting.get(key_a)).to eq("armed")
    expect(AuditLog.where(action: "update_site_setting").last.user_id).to eq(operator.id)
  end

  it "is rejected from a person's own session, and writes nothing" do
    request = park_as_instance!(key_a)

    decide("reject", request)

    expect(response).to have_http_status(:ok)
    expect(request.reload).to be_rejected
    expect(SiteSetting.find_by(key: key_a)).to be_nil
  end

  it "refuses an impersonation session on both verbs, leaving the request pending" do
    request = park_as_instance!(key_a)

    %w[approve reject].each do |verb|
      post "/api/v1/ai/autonomy/approvals/#{request.id}/#{verb}", params: {}.to_json,
                                                                  headers: impersonation_headers_for(operator)
      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include("own session")
    end
    expect(request.reload).to be_pending
    expect(SiteSetting.find_by(key: key_a)).to be_nil
  end

  it "does not mark a request whose stored params merely claim an instance without being human-only" do
    request = create(:ai_approval_request, account: account, status: "pending",
                                           request_data: { "params" => { "principal" => { "kind" => "instance" } } })

    expect(request.machine_requested?).to be(false)
  end

  it "carries the change card on the queue, filtered, and never in the description" do
    SiteSetting.set(key_a, "old-value")
    request = park_as_instance!(key_a, value: "new-value")

    get "/api/v1/ai/autonomy/approvals", headers: auth_headers_for(operator)

    row = json_response["data"].find { |r| r["id"] == request.id }
    expect(row["change_card"]).to include("tool" => "site_setting", "key" => key_a,
                                          "new_value" => "new-value", "current_value" => "old-value")
    expect(row["description"]).not_to include("new-value")
  end
end
