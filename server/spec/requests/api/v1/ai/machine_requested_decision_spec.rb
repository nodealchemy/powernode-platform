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
    Ai::Tools::SiteSettingTool.register_key(key_a, setting_type: "string", description: "decision spec", protected: true,
                                                    machine_parkable: true, ordering: ->(_requested, _current) { true })
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

  # `digest: :rendered` echoes the digest of the card this user is shown NOW, as
  # the queue does; an explicit string sends that; nil sends none.
  def decide(verb, request, user: operator, card_shown: true, digest: :rendered)
    body = card_shown ? { change_card_shown: true } : {}
    digest = rendered_digest(request, user: user) if digest == :rendered && card_shown
    body[:change_card_digest] = digest unless digest.nil? || digest == :rendered
    post "/api/v1/ai/autonomy/approvals/#{request.id}/#{verb}", params: body.to_json, headers: auth_headers_for(user)
  end

  def rendered_card(request, user: operator)
    get "/api/v1/ai/autonomy/approvals", headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok), response.body
    json_response["data"].find { |r| r["id"] == request.id }&.fetch("change_card")
  end

  def rendered_digest(request, user: operator) = rendered_card(request, user: user)&.fetch("digest", nil)

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

  it "refuses to approve without the card having been shown, and points at the queue" do
    request = park_as_instance!(key_a)

    decide("approve", request, card_shown: false)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_response["code"]).to eq("change_card_not_shown")
    expect(json_response["error"]).to include("/app/ai/control/approvals/queue")
    expect(request.reload).to be_pending
    expect(SiteSetting.find_by(key: key_a)).to be_nil
  end

  it "rejects without the card having been shown: a rejection changes nothing" do
    request = park_as_instance!(key_a)

    decide("reject", request, card_shown: false)

    expect(response).to have_http_status(:ok)
    expect(request.reload).to be_rejected
  end

  it "asks nothing extra of a request that carries no change card" do
    stub_const("SpecCardlessExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { success: true }
    end)
    gate = Ai::AutonomyGate.evaluate(action_category: "spec.cardless", executor_class: "SpecCardlessExecutor",
                                     params: {}, account: account, requested_by: operator)

    decide("approve", gate.approval_request, card_shown: false)

    expect(response).to have_http_status(:ok)
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

  # IMP-1765f6f09458 — the approval binds to a DIGEST of the card the person was
  # shown (key, new value, current value at render). The server recomputes it
  # for the decider's own session at decide time and refuses on a mismatch, so
  # a change to the setting between viewing and approving is never approved
  # blind. The client echoes the digest the server rendered; it never computes
  # one. It is required wherever the card attestation is (every card-bearing
  # request), so a person-parked request is bound the same way.
  describe "the digest of the card shown" do
    it "is rendered on the list and the detail, only to a viewer shown the current value" do
      SiteSetting.set(key_a, "old-value")
      request = park_as_instance!(key_a, value: "new-value")

      list_digest = rendered_digest(request)
      get "/api/v1/ai/autonomy/approvals/#{request.id}", headers: auth_headers_for(operator)
      expect(list_digest).to match(/\Av1:[0-9a-f]{64}\z/)
      expect(json_response.dig("data", "change_card", "digest")).to eq(list_digest)

      reader = user_with_permissions("ai.agents.read", "ai.autonomy.approve", account: account)
      card = rendered_card(request, user: reader)
      expect(card).to include("key" => key_a)
      expect(card).not_to have_key("current_value")
      expect(card).not_to have_key("digest")
    end

    it "refuses an approve that carries the attestation but no digest, and points at the queue" do
      request = park_as_instance!(key_a)

      decide("approve", request, digest: nil)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["code"]).to eq("change_card_digest_missing")
      expect(json_response["error"]).to include("/app/ai/control/approvals/queue")
      expect(request.reload).to be_pending
      expect(SiteSetting.find_by(key: key_a)).to be_nil
    end

    it "refuses when the setting changed since the card was viewed, leaving the request pending" do
      SiteSetting.set(key_a, "old-value")
      request = park_as_instance!(key_a, value: "new-value")
      stale = rendered_digest(request)
      SiteSetting.set(key_a, "changed-underneath")

      decide("approve", request, digest: stale)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["code"]).to eq("change_card_stale")
      expect(json_response["error"]).to include("changed since you viewed it")
      expect(request.reload).to be_pending
      expect(SiteSetting.get(key_a)).to eq("changed-underneath")

      # Viewed again, it approves.
      decide("approve", request)
      expect(response).to have_http_status(:ok), response.body
      expect(SiteSetting.get(key_a)).to eq("new-value")
    end

    it "refuses when the setting was unset after the card was viewed" do
      SiteSetting.set(key_a, "old-value")
      request = park_as_instance!(key_a, value: "new-value")
      stale = rendered_digest(request)
      SiteSetting.where(key: key_a).delete_all

      decide("approve", request, digest: stale)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["code"]).to eq("change_card_stale")
      expect(request.reload).to be_pending
    end

    it "treats a garbled digest as a mismatch, never as an error" do
      request = park_as_instance!(key_a)

      [ "not-a-digest", "", [ "v1:abc" ], { "v1" => "abc" } ].each do |garbled|
        post "/api/v1/ai/autonomy/approvals/#{request.id}/approve",
             params: { change_card_shown: true, change_card_digest: garbled }.to_json, headers: auth_headers_for(operator)
        expect(response).to have_http_status(:unprocessable_content), "#{garbled.inspect}: #{response.body}"
        expect(json_response["code"]).to eq(garbled == "" ? "change_card_digest_missing" : "change_card_stale")
      end
      expect(request.reload).to be_pending
    end

    it "refuses a decider whose own session is not shown the current value, leaving the request pending" do
      SiteSetting.set(key_a, "old-value")
      request = park_as_instance!(key_a, value: "new-value")
      operator_digest = rendered_digest(request)
      reader = user_with_permissions("ai.agents.read", "ai.autonomy.approve", account: account)

      # The real client path: the queue shows the reader a card without a digest and sends none.
      decide("approve", request, user: reader, digest: nil)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["code"]).to eq("change_card_not_readable")
      expect(json_response["error"]).not_to include("/app/ai/control/approvals/queue")

      # A borrowed digest is refused the same way, before any comparison.
      decide("approve", request, user: reader, digest: operator_digest)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["code"]).to eq("change_card_not_readable")

      expect(request.reload).to be_pending
      expect(SiteSetting.get(key_a)).to eq("old-value")
    end

    it "asks nothing of a reject: rejecting changes nothing" do
      request = park_as_instance!(key_a)

      decide("reject", request, card_shown: false, digest: nil)

      expect(response).to have_http_status(:ok)
      expect(request.reload).to be_rejected
    end

    it "binds a PERSON-parked request the same way: no digest refuses, the rendered one approves" do
      tool = Ai::Tools::SiteSettingTool.new(account: account, user: operator)
      tool.call_origin = "mcp_oauth"
      result = tool.execute(params: { action: "site_setting_set_protected", key: key_a, value: "armed" })
      request = Ai::ApprovalRequest.find(result[:data][:approval_request_id])
      expect(request.machine_requested?).to be(false)

      decide("approve", request, digest: nil)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["code"]).to eq("change_card_digest_missing")

      decide("approve", request)
      expect(response).to have_http_status(:ok), response.body
      expect(SiteSetting.get(key_a)).to eq("armed")
    end
  end
end
