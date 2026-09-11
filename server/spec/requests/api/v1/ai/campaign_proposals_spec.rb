# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::CampaignProposals", type: :request do
  let(:user) { user_with_permissions("ai.campaigns.read", "ai.campaigns.manage") }
  let(:account) { user.account }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/ai/campaign_proposals" do
    it "lists the account's proposals, filterable by status" do
      create(:ai_campaign_proposal, account: account, status: "proposed")
      create(:ai_campaign_proposal, :queued, account: account)
      create(:ai_campaign_proposal, account: create(:account)) # other account — not visible

      get "/api/v1/ai/campaign_proposals", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["total_count"]).to eq(2)

      get "/api/v1/ai/campaign_proposals?status=queued", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["total_count"]).to eq(1)
    end

    it "403s without ai.campaigns.read" do
      stranger = user_with_permissions
      get "/api/v1/ai/campaign_proposals", headers: auth_headers_for(stranger), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "reports the TRUE total_count, not the limited page size" do
      3.times { create(:ai_campaign_proposal, account: account) }
      get "/api/v1/ai/campaign_proposals?limit=1", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["proposals"].size).to eq(1)
      expect(json_response_data["total_count"]).to eq(3)
    end
  end

  describe "POST /api/v1/ai/campaign_proposals" do
    it "creates a proposal and dedupes a repeat target" do
      post "/api/v1/ai/campaign_proposals", headers: headers, as: :json,
           params: { title: "Audit billing", objective: "Find N+1s", scope: "core",
                     suggested_workload: "improvement-campaign", suggested_driver: "claude_code" }
      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data["status"]).to eq("proposed")
      expect(data["suggested_driver"]).to eq("claude_code")

      # Same target again → no duplicate row.
      post "/api/v1/ai/campaign_proposals", headers: headers, as: :json,
           params: { title: "Audit billing v2", objective: "Find N+1s", scope: "core" }
      expect(account.ai_campaign_proposals.count).to eq(1)
    end

    it "422s an invalid workload" do
      post "/api/v1/ai/campaign_proposals", headers: headers, as: :json,
           params: { title: "X", objective: "Y", suggested_workload: "nonsense" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "review transitions" do
    it "queue -> approve advances status and stamps the reviewer" do
      p = create(:ai_campaign_proposal, account: account)

      post "/api/v1/ai/campaign_proposals/#{p.id}/queue", headers: headers, as: :json
      expect_success_response
      expect(p.reload.status).to eq("queued")

      post "/api/v1/ai/campaign_proposals/#{p.id}/approve", headers: headers, as: :json
      expect_success_response
      expect(p.reload.status).to eq("approved")
      expect(p.reload.reviewed_by_id).to eq(user.id)
    end

    it "reject records a reason" do
      p = create(:ai_campaign_proposal, :queued, account: account)
      post "/api/v1/ai/campaign_proposals/#{p.id}/reject", headers: headers, as: :json,
           params: { reason: "out of scope" }
      expect_success_response
      expect(p.reload.status).to eq("rejected")
      expect(p.reload.rejection_reason).to eq("out of scope")
    end

    it "404s a proposal from another account" do
      other = create(:ai_campaign_proposal, account: create(:account))
      post "/api/v1/ai/campaign_proposals/#{other.id}/approve", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "spawn creates the campaign + dev-loop and back-links it" do
      p = create(:ai_campaign_proposal, :approved, account: account, title: "Add feature Z")

      post "/api/v1/ai/campaign_proposals/#{p.id}/spawn", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["status"]).to eq("spawned")
      expect(data["spawned_campaign"]["name"]).to eq("Add feature Z")
      expect(p.reload.spawned_campaign_id).to eq(data["spawned_campaign"]["id"])
    end
  end

  # Review finding (pre-existing MEDIUM): an account-switch session carries permissions
  # DELEGATED from another account, while these doors resolve proposals in the user's OWN
  # account. The gate must answer for the account whose proposal the call touches.
  describe "account-switch sessions: the permission is answered for the proposal's account" do
    let(:other_account) { create(:account) }

    # Role-backed and bounded by the delegator, who really holds what the role grants there.
    def delegation_from_other_account(to:, permissions:)
      grantor = create(:user, account: other_account, permissions: permissions)
      create(:account_delegation, account: other_account, delegated_user: to, delegated_by: grantor,
                                  role: grantor.roles.first)
    end

    def switched_headers(for_user, delegation)
      payload = { sub: for_user.id, account_id: other_account.id, primary_account_id: for_user.account_id,
                  delegation_id: delegation.id, type: "access", version: Security::JwtService::CURRENT_TOKEN_VERSION }
      { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
    end

    # ai.campaigns.read only in THIS account; manage delegated from the other one.
    def delegated_manager_headers
      member = create(:user, account: account, permissions: %w[ai.campaigns.read])
      delegation = delegation_from_other_account(to: member, permissions: %w[ai.campaigns.read ai.campaigns.manage])
      expect(delegation.effective_permissions).to include("ai.campaigns.manage") # precondition: the grant is real
      switched_headers(member, delegation)
    end

    # ai.campaigns.manage in THIS account; its switched session's delegation does not carry it.
    def local_manager_switched_headers
      delegation = delegation_from_other_account(to: user, permissions: %w[ai.campaigns.read])
      expect(delegation.effective_permissions).not_to include("ai.campaigns.manage") # precondition
      switched_headers(user, delegation)
    end

    def expect_door_refusal
      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include("Permission denied: ai.campaigns.manage")
    end

    it "create: refuses delegated manage, and a manager of this account still proposes" do
      post "/api/v1/ai/campaign_proposals", headers: delegated_manager_headers, as: :json,
           params: { title: "Delegated", objective: "Delegated objective" }
      expect_door_refusal
      expect(account.ai_campaign_proposals.count).to eq(0)

      post "/api/v1/ai/campaign_proposals", headers: local_manager_switched_headers, as: :json,
           params: { title: "Mine", objective: "My objective" }
      expect(response).to have_http_status(:created)
      expect(account.ai_campaign_proposals.pluck(:title)).to eq(["Mine"])
    end

    it "queue: refuses delegated manage, and a manager of this account still queues" do
      p = create(:ai_campaign_proposal, account: account)

      post "/api/v1/ai/campaign_proposals/#{p.id}/queue", headers: delegated_manager_headers, as: :json
      expect_door_refusal
      expect(p.reload.status).to eq("proposed")

      post "/api/v1/ai/campaign_proposals/#{p.id}/queue", headers: local_manager_switched_headers, as: :json
      expect_success_response
      expect(p.reload.status).to eq("queued")
    end

    it "approve: refuses delegated manage, and a manager of this account still approves" do
      p = create(:ai_campaign_proposal, :queued, account: account)

      post "/api/v1/ai/campaign_proposals/#{p.id}/approve", headers: delegated_manager_headers, as: :json
      expect_door_refusal
      expect(p.reload.status).to eq("queued")

      post "/api/v1/ai/campaign_proposals/#{p.id}/approve", headers: local_manager_switched_headers, as: :json
      expect_success_response
      expect(p.reload.status).to eq("approved")
      expect(p.reviewed_by_id).to eq(user.id)
    end

    it "reject: refuses delegated manage, and a manager of this account still rejects" do
      p = create(:ai_campaign_proposal, :queued, account: account)

      post "/api/v1/ai/campaign_proposals/#{p.id}/reject", headers: delegated_manager_headers, as: :json,
           params: { reason: "delegated" }
      expect_door_refusal
      expect(p.reload.status).to eq("queued")

      post "/api/v1/ai/campaign_proposals/#{p.id}/reject", headers: local_manager_switched_headers, as: :json,
           params: { reason: "mine" }
      expect_success_response
      expect(p.reload.status).to eq("rejected")
    end

    it "spawn: refuses delegated manage, and a manager of this account still spawns" do
      p = create(:ai_campaign_proposal, :approved, account: account, title: "Spawn me")

      post "/api/v1/ai/campaign_proposals/#{p.id}/spawn", headers: delegated_manager_headers, as: :json
      expect_door_refusal
      expect(p.reload.status).to eq("approved")
      expect(account.ai_campaigns.count).to eq(0)

      post "/api/v1/ai/campaign_proposals/#{p.id}/spawn", headers: local_manager_switched_headers, as: :json
      expect_success_response
      expect(p.reload.status).to eq("spawned")
    end
  end
end
