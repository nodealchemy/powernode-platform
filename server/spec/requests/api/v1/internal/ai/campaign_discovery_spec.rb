# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Ai::CampaignDiscovery", type: :request do
  include_context "internal api auth"

  def pending_rec(account)
    create(:ai_improvement_recommendation, account: account, status: "pending",
           target_type: "Devops::GitRepository", target_id: SecureRandom.uuid)
  end

  it "scans active accounts and upserts campaign proposals" do
    pending_rec(internal_account)

    post "/api/v1/internal/ai/campaign_discovery/scan", headers: service_headers

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["proposals_created"]).to be >= 1
    expect(internal_account.ai_campaign_proposals.count).to eq(1)
  end

  it "skips suspended accounts (kill-switch)" do
    internal_account.update!(ai_suspended: true)
    pending_rec(internal_account)

    post "/api/v1/internal/ai/campaign_discovery/scan", headers: service_headers

    expect(response).to have_http_status(:ok)
    expect(internal_account.ai_campaign_proposals.count).to eq(0)
  end
end
