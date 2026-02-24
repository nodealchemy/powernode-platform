# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing Campaigns API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("marketing.campaigns.read", "marketing.campaigns.manage", "marketing.campaigns.execute", account: account) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/marketing/campaigns" do
    let!(:campaign1) { create(:marketing_campaign, account: account) }
    let!(:campaign2) { create(:marketing_campaign, :active, account: account) }
    let!(:other_account_campaign) { create(:marketing_campaign) }

    it "returns campaigns for the account" do
      get "/api/v1/marketing/campaigns", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(2)
    end

    it "filters by status" do
      get "/api/v1/marketing/campaigns", params: { status: "active" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(1)
      expect(json_response["data"]["items"].first["status"]).to eq("active")
    end

    it "filters by campaign type" do
      social = create(:marketing_campaign, :social, account: account)
      get "/api/v1/marketing/campaigns", params: { campaign_type: "social" }, headers: headers

      expect(response).to have_http_status(:ok)
      items = json_response["data"]["items"]
      expect(items.map { |i| i["id"] }).to include(social.id)
    end

    it "requires authentication" do
      get "/api/v1/marketing/campaigns"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires permission" do
      no_perm_user = user_with_permissions(account: account)
      get "/api/v1/marketing/campaigns", headers: auth_headers_for(no_perm_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/marketing/campaigns/:id" do
    let!(:campaign) { create(:marketing_campaign, account: account) }

    it "returns campaign details" do
      get "/api/v1/marketing/campaigns/#{campaign.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["campaign"]["id"]).to eq(campaign.id)
      expect(json_response["data"]["campaign"]["name"]).to eq(campaign.name)
    end

    it "returns 404 for non-existent campaign" do
      get "/api/v1/marketing/campaigns/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for campaign from another account" do
      other = create(:marketing_campaign)
      get "/api/v1/marketing/campaigns/#{other.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/marketing/campaigns" do
    let(:valid_params) do
      {
        campaign: {
          name: "Launch Campaign",
          campaign_type: "email",
          budget_cents: 50_000,
          channels: ["email"],
          tags: ["launch"]
        }
      }
    end

    it "creates a new campaign" do
      expect {
        post "/api/v1/marketing/campaigns", params: valid_params.to_json, headers: headers
      }.to change(Marketing::Campaign, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["campaign"]["name"]).to eq("Launch Campaign")
      expect(json_response["data"]["campaign"]["status"]).to eq("draft")
    end

    it "validates required fields" do
      post "/api/v1/marketing/campaigns",
           params: { campaign: { name: "" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/marketing/campaigns/:id" do
    let!(:campaign) { create(:marketing_campaign, account: account) }

    it "updates the campaign" do
      patch "/api/v1/marketing/campaigns/#{campaign.id}",
            params: { campaign: { name: "Updated Name" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["campaign"]["name"]).to eq("Updated Name")
      expect(campaign.reload.name).to eq("Updated Name")
    end
  end

  describe "DELETE /api/v1/marketing/campaigns/:id" do
    let!(:campaign) { create(:marketing_campaign, account: account) }

    it "deletes the campaign" do
      expect {
        delete "/api/v1/marketing/campaigns/#{campaign.id}", headers: headers
      }.to change(Marketing::Campaign, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/marketing/campaigns/:id/execute" do
    let!(:campaign) { create(:marketing_campaign, account: account) }

    it "executes the campaign" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/execute", headers: headers

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq("active")
    end

    it "returns error for invalid state transition" do
      campaign.activate!
      campaign.complete!

      post "/api/v1/marketing/campaigns/#{campaign.id}/execute", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/marketing/campaigns/:id/pause" do
    let!(:campaign) { create(:marketing_campaign, :active, account: account) }

    it "pauses an active campaign" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/pause", headers: headers

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq("paused")
    end
  end

  describe "POST /api/v1/marketing/campaigns/:id/resume" do
    let!(:campaign) { create(:marketing_campaign, :paused, account: account) }

    it "resumes a paused campaign" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/resume", headers: headers

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq("active")
    end
  end

  describe "POST /api/v1/marketing/campaigns/:id/archive" do
    let!(:campaign) { create(:marketing_campaign, :completed, account: account) }

    it "archives a completed campaign" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/archive", headers: headers

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq("archived")
    end
  end

  describe "POST /api/v1/marketing/campaigns/:id/clone" do
    let!(:campaign) { create(:marketing_campaign, account: account) }

    it "clones the campaign" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/clone", headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["campaign"]["name"]).to include("(Copy)")
      expect(json_response["data"]["campaign"]["status"]).to eq("draft")
    end
  end

  describe "GET /api/v1/marketing/campaigns/statistics" do
    before do
      create(:marketing_campaign, account: account)
      create(:marketing_campaign, :active, account: account)
    end

    it "returns campaign statistics" do
      get "/api/v1/marketing/campaigns/statistics", headers: headers

      expect(response).to have_http_status(:ok)
      stats = json_response["data"]["statistics"]
      expect(stats["total"]).to eq(2)
      expect(stats["by_status"]).to be_present
    end
  end
end
