# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing Campaign Contents API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("marketing.campaigns.read", "marketing.campaigns.manage", "marketing.content.approve", account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:campaign) { create(:marketing_campaign, account: account) }

  describe "GET /api/v1/marketing/campaigns/:campaign_id/contents" do
    let!(:content1) { create(:marketing_campaign_content, campaign: campaign) }
    let!(:content2) { create(:marketing_campaign_content, :twitter, campaign: campaign) }

    it "returns contents for the campaign" do
      get "/api/v1/marketing/campaigns/#{campaign.id}/contents", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(2)
    end

    it "filters by channel" do
      get "/api/v1/marketing/campaigns/#{campaign.id}/contents",
          params: { channel: "twitter" },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(1)
      expect(json_response["data"]["items"].first["channel"]).to eq("twitter")
    end

    it "requires authentication" do
      get "/api/v1/marketing/campaigns/#{campaign.id}/contents"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/marketing/campaigns/:campaign_id/contents/:id" do
    let!(:content) { create(:marketing_campaign_content, campaign: campaign) }

    it "returns content details" do
      get "/api/v1/marketing/campaigns/#{campaign.id}/contents/#{content.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["content"]["id"]).to eq(content.id)
      expect(json_response["data"]["content"]["body"]).to be_present
    end
  end

  describe "POST /api/v1/marketing/campaigns/:campaign_id/contents" do
    let(:valid_params) do
      {
        content: {
          channel: "email",
          variant_name: "Main Variant",
          subject: "Test Subject",
          body: "<p>Test body content</p>",
          cta_text: "Click Here",
          cta_url: "https://example.com"
        }
      }
    end

    it "creates new content" do
      expect {
        post "/api/v1/marketing/campaigns/#{campaign.id}/contents",
             params: valid_params.to_json,
             headers: headers
      }.to change(Marketing::CampaignContent, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["content"]["channel"]).to eq("email")
    end

    it "validates required fields" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/contents",
           params: { content: { channel: "" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/marketing/campaigns/:campaign_id/contents/:id" do
    let!(:content) { create(:marketing_campaign_content, campaign: campaign) }

    it "updates the content" do
      patch "/api/v1/marketing/campaigns/#{campaign.id}/contents/#{content.id}",
            params: { content: { subject: "Updated Subject" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["content"]["subject"]).to eq("Updated Subject")
    end
  end

  describe "DELETE /api/v1/marketing/campaigns/:campaign_id/contents/:id" do
    let!(:content) { create(:marketing_campaign_content, campaign: campaign) }

    it "deletes the content" do
      expect {
        delete "/api/v1/marketing/campaigns/#{campaign.id}/contents/#{content.id}", headers: headers
      }.to change(Marketing::CampaignContent, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/marketing/campaigns/:campaign_id/contents/generate" do
    it "generates AI content" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/contents/generate",
           params: { channel: "email", variant_count: 2 }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      contents = json_response["data"]["contents"]
      expect(contents.length).to eq(2)
      expect(contents.first["ai_generated"]).to be true
    end
  end

  describe "POST /api/v1/marketing/campaigns/:campaign_id/contents/:id/approve" do
    let!(:content) { create(:marketing_campaign_content, campaign: campaign) }

    it "approves the content" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/contents/#{content.id}/approve", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["content"]["status"]).to eq("approved")
    end

    it "requires approve permission" do
      no_perm_user = user_with_permissions("marketing.campaigns.read", account: account)
      post "/api/v1/marketing/campaigns/#{campaign.id}/contents/#{content.id}/approve",
           headers: auth_headers_for(no_perm_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/marketing/campaigns/:campaign_id/contents/:id/reject" do
    let!(:content) { create(:marketing_campaign_content, campaign: campaign) }

    it "rejects the content" do
      post "/api/v1/marketing/campaigns/#{campaign.id}/contents/#{content.id}/reject", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["content"]["status"]).to eq("rejected")
    end
  end
end
