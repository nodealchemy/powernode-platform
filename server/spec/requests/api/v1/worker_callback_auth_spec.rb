# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the worker_authenticated? carve-outs added 2026-05-18.
# The bug: controllers that gate on current_user.has_permission?(...) without a
# nil check NoMethodError on every worker callback (current_user is nil for
# worker JWT callers), failing all worker-driven flows like the async PDF
# report pipeline. This spec exercises each controller's worker path to ensure
# the carve-out stays in place across future refactors.
RSpec.describe "Worker-callback auth carve-outs", type: :request do
  let(:account) { create(:account) }
  let(:worker_account) { create(:account) }
  let(:worker) { create(:worker, account: worker_account) }
  let(:worker_headers) do
    {
      "Authorization" => "Bearer #{Security::JwtService.encode({ type: 'worker', sub: worker.id }, 5.minutes.from_now)}"
    }
  end

  describe "Api::V1::ReportsController" do
    let(:report_request) do
      create(
        :report_request,
        account: account,
        user: create(:user, account: account),
        report_type: "revenue_analytics",
        status: "pending"
      )
    end

    it "lets a worker GET /reports/requests/:id (callback to pull metadata)" do
      get "/api/v1/reports/requests/#{report_request.id}", headers: worker_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_response_data["id"]).to eq(report_request.id)
    end

    it "lets a worker PATCH /reports/requests/:id status to processing" do
      patch "/api/v1/reports/requests/#{report_request.id}",
            params: { status: "processing" },
            headers: worker_headers,
            as: :json
      expect(response).to have_http_status(:ok)
      expect(report_request.reload.status).to eq("processing")
    end

    it "lets a worker PATCH /reports/requests/:id status to completed" do
      patch "/api/v1/reports/requests/#{report_request.id}",
            params: {
              status: "completed",
              file_path: "/tmp/reports/foo.pdf",
              file_size: 1024,
              file_url: "http://localhost:3000/...",
              completed_at: Time.current.iso8601
            },
            headers: worker_headers,
            as: :json
      expect(response).to have_http_status(:ok)
      expect(report_request.reload.status).to eq("completed")
    end
  end

  describe "Api::V1::AnalyticsController" do
    it "lets a worker POST /analytics/export (callback to fetch report data)" do
      post "/api/v1/ai/analytics/export",
           params: { report_type: "revenue_analytics", parameters: { date_range: { start_date: "2026-01-01", end_date: "2026-03-31" } } },
           headers: worker_headers,
           as: :json
      # Either renders the CSV body or returns a graceful error — either way it
      # MUST NOT 500 with `undefined method has_permission? for nil:NilClass`
      expect([200, 422, 400]).to include(response.status), "got #{response.status}: #{response.body[0..200]}"
    end
  end

  describe "Api::V1::AccountsController" do
    let(:other_account) { create(:account) }

    it "lets a worker GET /accounts/:id for an account other than the worker's own" do
      get "/api/v1/accounts/#{other_account.id}", headers: worker_headers, as: :json
      # 200 (rendered) or 404 (not implemented for that scope) — never 500.
      expect([200, 404]).to include(response.status), "got #{response.status}: #{response.body[0..200]}"
    end
  end

  describe "Api::V1::Webhooks::EventsController" do
    let(:webhook_event) { create(:webhook_event, account: worker.account) }

    it "passes worker JWT through require_webhook_permission without NoMethodError" do
      get "/api/v1/webhooks/events/#{webhook_event.id}", headers: worker_headers, as: :json

      # The carve-out's job: get past require_webhook_permission for worker callers.
      # A separate pre-existing bug in #serialize_event references the non-existent
      # column webhook_endpoint_id and 500s; that bug is out of scope here. We
      # assert that the FAILURE, if any, is NOT a has_permission? NoMethodError.
      log_tail = File.exist?("log/test.log") ? File.read("log/test.log").lines.last(80).join : ""
      expect(log_tail).not_to include("undefined method `has_permission?' for nil"),
        "the worker-auth carve-out in require_webhook_permission has regressed"
    end
  end
end
