# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing Social Media Accounts API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("marketing.social.read", "marketing.social.manage", account: account) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/marketing/social_accounts" do
    let!(:twitter) { create(:marketing_social_media_account, :twitter, account: account) }
    let!(:linkedin) { create(:marketing_social_media_account, :linkedin, account: account) }
    let!(:other_account) { create(:marketing_social_media_account) }

    it "returns social accounts for the account" do
      get "/api/v1/marketing/social_accounts", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["items"].length).to eq(2)
    end

    it "filters by platform" do
      get "/api/v1/marketing/social_accounts", params: { platform: "twitter" }, headers: headers

      expect(response).to have_http_status(:ok)
      items = json_response["data"]["items"]
      expect(items.length).to eq(1)
      expect(items.first["platform"]).to eq("twitter")
    end

    it "requires authentication" do
      get "/api/v1/marketing/social_accounts"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires permission" do
      no_perm_user = user_with_permissions(account: account)
      get "/api/v1/marketing/social_accounts", headers: auth_headers_for(no_perm_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/marketing/social_accounts/:id" do
    let!(:social_account) { create(:marketing_social_media_account, account: account) }

    it "returns account details" do
      get "/api/v1/marketing/social_accounts/#{social_account.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["social_account"]["id"]).to eq(social_account.id)
      expect(json_response["data"]["social_account"]["platform"]).to eq(social_account.platform)
    end

    it "returns 404 for non-existent account" do
      get "/api/v1/marketing/social_accounts/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/marketing/social_accounts" do
    let(:valid_params) do
      {
        social_account: {
          platform: "twitter",
          platform_account_id: "12345",
          platform_username: "testaccount",
          token_expires_at: 30.days.from_now.iso8601
        }
      }
    end

    it "creates a new social account" do
      expect {
        post "/api/v1/marketing/social_accounts", params: valid_params.to_json, headers: headers
      }.to change(Marketing::SocialMediaAccount, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["social_account"]["platform"]).to eq("twitter")
    end

    it "validates required fields" do
      post "/api/v1/marketing/social_accounts",
           params: { social_account: { platform: "invalid" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/marketing/social_accounts/:id" do
    let!(:social_account) { create(:marketing_social_media_account, account: account) }

    it "updates the account" do
      patch "/api/v1/marketing/social_accounts/#{social_account.id}",
            params: { social_account: { platform_username: "updated_user" } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["social_account"]["platform_username"]).to eq("updated_user")
    end
  end

  describe "DELETE /api/v1/marketing/social_accounts/:id" do
    let!(:social_account) { create(:marketing_social_media_account, account: account) }

    it "deletes the account" do
      expect {
        delete "/api/v1/marketing/social_accounts/#{social_account.id}", headers: headers
      }.to change(Marketing::SocialMediaAccount, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/marketing/social_accounts/:id/test" do
    let!(:social_account) { create(:marketing_social_media_account, account: account) }

    it "returns not_implemented for stub adapters" do
      post "/api/v1/marketing/social_accounts/#{social_account.id}/test", headers: headers

      # The stub adapters raise NotImplementedError
      expect(response).to have_http_status(:not_implemented)
    end
  end

  describe "POST /api/v1/marketing/social_accounts/:id/refresh_token" do
    let!(:social_account) { create(:marketing_social_media_account, account: account) }

    it "returns not_implemented for stub adapters" do
      post "/api/v1/marketing/social_accounts/#{social_account.id}/refresh_token", headers: headers

      expect(response).to have_http_status(:not_implemented)
    end
  end
end
