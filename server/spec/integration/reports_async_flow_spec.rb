# frozen_string_literal: true

require "rails_helper"

# Exercises the full async reports lifecycle end-to-end with real database +
# real controller + real model, mocking only the worker dispatch boundary
# (WorkerJobService.enqueue_job). Simulates the worker's PATCH callbacks
# directly to drive the state machine forward, then verifies the download
# endpoint streams the file Bytes the worker would have written.
RSpec.describe "Reports async flow integration", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  before do
    user.grant_permission("analytics.export")
    # Capture worker dispatches so we can assert on the contract without
    # actually crossing the worker boundary.
    allow(WorkerJobService).to receive(:enqueue_job)
  end

  it "POST -> poll -> worker-PATCH -> download yields the rendered file" do
    # 1. Client posts a report request.
    post "/api/v1/reports/requests",
         params: {
           template_id: "revenue_analytics",
           format: "pdf",
           name: "Integration Revenue Q1",
           parameters: { date_range: { start_date: "2026-01-01", end_date: "2026-03-31" } }
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:accepted)
    created = json_response_data
    request_id = created["id"]

    # 2. The controller created the row and dispatched the worker job.
    report_request = ReportRequest.find(request_id)
    expect(report_request.status).to eq("pending")
    expect(report_request.report_type).to eq("revenue_analytics")
    expect(report_request.format).to eq("pdf")
    expect(report_request.parameters.dig("date_range", "start_date")).to eq("2026-01-01")
    expect(WorkerJobService).to have_received(:enqueue_job).with(
      "Reports::GenerateReportJob",
      hash_including(args: [request_id], queue: "reports")
    )

    # 3. Client polls and sees pending.
    get "/api/v1/reports/requests/#{request_id}", headers: headers, as: :json
    expect(json_response_data["status"]).to eq("pending")

    # 4. Worker (simulated) marks processing.
    patch "/api/v1/reports/requests/#{request_id}",
          params: { status: "processing" },
          headers: headers,
          as: :json
    expect(response).to have_http_status(:ok)

    # 5. Worker (simulated) writes a file + marks completed via the same PATCH.
    reports_dir = Rails.root.join("tmp", "reports")
    FileUtils.mkdir_p(reports_dir)
    file_path = reports_dir.join("integration_#{request_id}.pdf").to_s
    File.binwrite(file_path, "%PDF-1.4\nfake bytes for integration spec\n")

    patch "/api/v1/reports/requests/#{request_id}",
          params: {
            status: "completed",
            file_path: file_path,
            file_size: File.size(file_path),
            file_url: "http://localhost:3000/api/v1/reports/requests/#{request_id}/download",
            content_type: "application/pdf",
            completed_at: Time.current.iso8601
          },
          headers: headers,
          as: :json
    expect(response).to have_http_status(:ok)

    # 6. Client polls and sees completed with file metadata.
    get "/api/v1/reports/requests/#{request_id}", headers: headers, as: :json
    completed = json_response_data
    expect(completed["status"]).to eq("completed")
    expect(completed["file_url"]).to include("/download")
    expect(completed["file_size"]).to be > 0

    # 7. Client downloads the file — bytes match what the worker wrote.
    get "/api/v1/reports/requests/#{request_id}/download", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.body).to start_with("%PDF-1.4")

    # 8. Audit log captured the state changes.
    actions = AuditLog.where(resource_id: request_id).order(:created_at).pluck(:action)
    expect(actions).to include("report_request_processing", "report_request_completed")

    File.delete(file_path) if File.exist?(file_path)
  end

  it "rejects taxonomy outside the canonical six" do
    post "/api/v1/reports/requests",
         params: { template_id: "revenue_report", format: "pdf", name: "stale" },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(WorkerJobService).not_to have_received(:enqueue_job)
  end

  it "rejects formats outside pdf | csv" do
    post "/api/v1/reports/requests",
         params: { template_id: "revenue_analytics", format: "xlsx", name: "bad" },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(WorkerJobService).not_to have_received(:enqueue_job)
  end

  it "cancel during pending transitions cleanly" do
    post "/api/v1/reports/requests",
         params: { template_id: "customer_analytics", format: "csv", name: "to-cancel" },
         headers: headers,
         as: :json
    request_id = json_response_data["id"]

    delete "/api/v1/reports/requests/#{request_id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(ReportRequest.find(request_id).status).to eq("cancelled")
  end
end
