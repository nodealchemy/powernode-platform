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
  end
end
