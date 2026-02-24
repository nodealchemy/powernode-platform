# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Marketing Analytics API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("marketing.analytics.read", account: account) }
  let(:headers) { auth_headers_for(user) }

  let!(:campaign) { create(:marketing_campaign, :active, account: account) }
  let!(:metric) { create(:marketing_campaign_metric, campaign: campaign) }

  describe "GET /api/v1/marketing/analytics/overview" do
    it "returns overview analytics" do
      get "/api/v1/marketing/analytics/overview", headers: headers

      expect(response).to have_http_status(:ok)
      overview = json_response["data"]["overview"]
      expect(overview["campaigns"]).to include("total", "active")
      expect(overview["totals"]).to include("sends", "deliveries", "clicks")
      expect(overview["rates"]).to include("open_rate", "click_rate")
      expect(overview["budget"]).to include("total_budget_cents")
    end

    it "supports date range filtering" do
      get "/api/v1/marketing/analytics/overview",
          params: { start_date: 1.week.ago.to_date.to_s, end_date: Date.current.to_s },
          headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "requires authentication" do
      get "/api/v1/marketing/analytics/overview"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires permission" do
      no_perm_user = user_with_permissions(account: account)
      get "/api/v1/marketing/analytics/overview", headers: auth_headers_for(no_perm_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/marketing/analytics/campaigns/:id" do
    it "returns campaign detail analytics" do
      get "/api/v1/marketing/analytics/campaigns/#{campaign.id}", headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response["data"]["campaign_analytics"]
      expect(data["campaign"]).to be_present
      expect(data["totals"]).to be_present
      expect(data["rates"]).to be_present
      expect(data["time_series"]).to be_an(Array)
    end

    it "returns 404 for non-existent campaign" do
      get "/api/v1/marketing/analytics/campaigns/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/marketing/analytics/channels" do
    it "returns channel breakdown" do
      get "/api/v1/marketing/analytics/channels", headers: headers

      expect(response).to have_http_status(:ok)
      channels = json_response["data"]["channels"]
      expect(channels).to be_a(Hash)
    end
  end

  describe "GET /api/v1/marketing/analytics/roi" do
    it "returns ROI analysis" do
      get "/api/v1/marketing/analytics/roi", headers: headers

      expect(response).to have_http_status(:ok)
      roi = json_response["data"]["roi"]
      expect(roi["overall"]).to include("total_cost_cents", "total_revenue_cents", "roi_percentage")
      expect(roi["by_campaign"]).to be_an(Array)
    end
  end

  describe "GET /api/v1/marketing/analytics/top_performers" do
    it "returns top performing campaigns" do
      get "/api/v1/marketing/analytics/top_performers", headers: headers

      expect(response).to have_http_status(:ok)
      performers = json_response["data"]["top_performers"]
      expect(performers).to be_an(Array)
    end

    it "accepts metric parameter" do
      get "/api/v1/marketing/analytics/top_performers",
          params: { metric: "revenue_cents", limit: 5 },
          headers: headers

      expect(response).to have_http_status(:ok)
    end
  end
end
