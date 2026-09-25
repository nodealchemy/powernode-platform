# frozen_string_literal: true

require "rails_helper"

# fc-21: #index and #latest were deleted along with their only caller (the
# unrouted admin DailySummariesPage/Panel frontend) — this pins the one
# action that stays, POST .../daily_summaries/generate, whose live caller is
# the scheduled DailySummaryJob (worker/app/jobs/daily_summary_job.rb).
RSpec.describe "Api::V1::Admin::DailySummaries", type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ "admin.access" ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe "POST /api/v1/admin/daily_summaries/generate" do
    it "creates a published daily-summary Page for the given date" do
      post "/api/v1/admin/daily_summaries/generate",
           params: { date: "2026-05-16" },
           headers: auth_headers_for(admin_user), as: :json

      expect_success_response
      summary = json_response_data["summary"]
      expect(summary["slug"]).to eq("daily-summary-2026-05-16")

      page = Page.find_by(account: account, slug: "daily-summary-2026-05-16")
      expect(page).not_to be_nil
      expect(page.status).to eq("published")
    end

    it "defaults to yesterday's date when none is given" do
      post "/api/v1/admin/daily_summaries/generate",
           headers: auth_headers_for(admin_user), as: :json

      expect_success_response
      expect(Page.exists?(account: account, slug: "daily-summary-#{Date.yesterday.iso8601}")).to be(true)
    end

    it "is idempotent by slug — calling it twice for the same date returns the existing Page, not a duplicate" do
      post "/api/v1/admin/daily_summaries/generate",
           params: { date: "2026-05-16" },
           headers: auth_headers_for(admin_user), as: :json
      first_id = json_response_data["summary"]["id"]

      post "/api/v1/admin/daily_summaries/generate",
           params: { date: "2026-05-16" },
           headers: auth_headers_for(admin_user), as: :json

      expect_success_response
      expect(json_response_data["summary"]["id"]).to eq(first_id)
      expect(Page.where(account: account, slug: "daily-summary-2026-05-16").count).to eq(1)
    end

    it "rejects an invalid date with 422" do
      post "/api/v1/admin/daily_summaries/generate",
           params: { date: "not-a-date" },
           headers: auth_headers_for(admin_user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires admin.access" do
      post "/api/v1/admin/daily_summaries/generate",
           headers: auth_headers_for(regular_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the deleted actions" do
    it "no longer routes GET /api/v1/admin/daily_summaries (index)" do
      get "/api/v1/admin/daily_summaries", headers: auth_headers_for(admin_user), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "no longer routes GET /api/v1/admin/daily_summaries/latest" do
      get "/api/v1/admin/daily_summaries/latest", headers: auth_headers_for(admin_user), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
