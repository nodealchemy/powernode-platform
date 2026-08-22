# frozen_string_literal: true

require "rails_helper"

# Server half of the report-pipeline jobs the worker now defines
# (Reports::ScheduledReportSweepJob / Reports::CleanupOldReportsJob).
#
# process_scheduled is where a sweep actually turns into a report; cleanup_old
# is the destructive half. The retention-boundary examples below are the ones
# protecting real data: an in-retention artifact must survive the sweep.
RSpec.describe "Internal::Reports", type: :request do
  include_context "internal api auth"

  let(:reports_dir) { Rails.root.join("tmp", "reports") }

  before do
    FileUtils.mkdir_p(reports_dir)
  end

  describe "POST /api/v1/internal/reports/process_scheduled" do
    let(:path) { "/api/v1/internal/reports/process_scheduled" }

    before do
      # Stub only the HTTP hop to the worker; the ReportRequest row is created
      # for real so "the sweep produced a report" is an observable, not a mock.
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
    end

    def due_report(account:)
      report = create(:scheduled_report, account: account, frequency: "daily")
      report.update_column(:next_run_at, 1.hour.ago)
      report
    end

    it "produces a ReportRequest for a due scheduled report" do
      report = due_report(account: internal_account)

      expect {
        post path, headers: service_headers
      }.to change { ReportRequest.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("data", "reports_processed")).to eq(1)

      created = ReportRequest.order(:created_at).last
      expect(created.report_type).to eq(report.report_type)
      expect(created.account_id).to eq(report.account_id)
    end

    it "enqueues the generation job for the request it created" do
      due_report(account: internal_account)

      post path, headers: service_headers

      expect(WorkerJobService).to have_received(:enqueue_job)
        .with("Reports::GenerateReportJob", hash_including(queue: "reports"))
    end

    it "advances the schedule so the next sweep does not re-dispatch it" do
      report = due_report(account: internal_account)

      post path, headers: service_headers
      report.reload

      expect(report.next_run_at).to be > Time.current
      expect(ScheduledReport.due_for_execution).not_to include(report)
    end

    # The negative case: a report that is not yet due must not be dispatched.
    it "leaves a not-yet-due scheduled report alone" do
      future = create(:scheduled_report, account: internal_account, frequency: "daily")
      future.update_column(:next_run_at, 2.days.from_now)

      expect {
        post path, headers: service_headers
      }.not_to change { ReportRequest.count }

      expect(JSON.parse(response.body).dig("data", "reports_processed")).to eq(0)
      expect(future.reload.next_run_at).to be > 1.day.from_now
    end

    it "leaves an inactive scheduled report alone even when its next_run_at has passed" do
      inactive = create(:scheduled_report, :inactive, account: internal_account)
      inactive.update_column(:next_run_at, 1.hour.ago)

      expect {
        post path, headers: service_headers
      }.not_to change { ReportRequest.count }
    end

    it "advances the schedule of a report whose dispatch raised, so the sweep cannot hot-loop" do
      report = due_report(account: internal_account)
      allow(PdfReportService).to receive(:enqueue!).and_raise(StandardError, "boom")

      post path, headers: service_headers

      expect(JSON.parse(response.body).dig("data", "reports_failed")).to eq(1)
      expect(report.reload.next_run_at).to be > Time.current
    end

    # A row created but never enqueued would sit "pending" forever, and the
    # retention sweep deliberately never reaps pending rows.
    it "marks the request failed when the worker enqueue is refused" do
      due_report(account: internal_account)
      allow(WorkerJobService).to receive(:enqueue_job)
        .and_raise(WorkerJobService::WorkerServiceError, "worker down")

      post path, params: {}.to_json, headers: service_headers

      expect(JSON.parse(response.body).dig("data", "reports_failed")).to eq(1)
      created = ReportRequest.order(:created_at).last
      expect(created.status).to eq("failed")
      expect(created.error_message).to match(/Could not enqueue/)
    end

    it "stops dispatching once the sweep budget is spent" do
      stub_const("Api::V1::Internal::ReportsController::MAX_SWEEP_SECONDS", 0)
      2.times { due_report(account: internal_account) }

      expect {
        post path, headers: service_headers
      }.not_to change { ReportRequest.count }

      expect(JSON.parse(response.body).dig("data", "due_count")).to eq(2)
    end

    it "caps how many reports one sweep dispatches" do
      stub_const("Api::V1::Internal::ReportsController::MAX_REPORTS_PER_SWEEP", 2)
      3.times { due_report(account: internal_account) }

      expect {
        post path, headers: service_headers
      }.to change { ReportRequest.count }.by(2)

      body = JSON.parse(response.body)
      expect(body.dig("data", "due_count")).to eq(3)
      expect(body.dig("data", "remaining_count")).to eq(1)
    end
  end

  describe "POST /api/v1/internal/reports/cleanup_old" do
    let(:path) { "/api/v1/internal/reports/cleanup_old" }

    def artifact(name)
      file = reports_dir.join(name).to_s
      File.write(file, "pdf-bytes")
      file
    end

    def aged_request(age:, status: "completed", file: nil)
      request = create(:report_request, account: internal_account, status: status, file_path: file)
      request.update_column(:created_at, age)
      request
    end

    it "deletes a finished request past the retention boundary, and its artifact" do
      file = artifact("old.pdf")
      old = aged_request(age: 90.days.ago, file: file)

      post path, params: { days_old: 30 }.to_json, headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(ReportRequest.where(id: old.id)).not_to exist
      expect(File.exist?(file)).to be false
      expect(JSON.parse(response.body).dig("data", "deleted_count")).to eq(1)
    end

    # THE negative case. If this passes vacuously the whole guard is worthless,
    # so it asserts on a specific row id AND on its file still being readable.
    it "leaves an IN-RETENTION request and its artifact completely intact" do
      kept_file = artifact("recent.pdf")
      kept = aged_request(age: 5.days.ago, file: kept_file)
      doomed_file = artifact("ancient.pdf")
      doomed = aged_request(age: 90.days.ago, file: doomed_file)

      post path, params: { days_old: 30 }.to_json, headers: service_headers

      # The sweep really did delete something — otherwise "kept survived" proves nothing.
      expect(ReportRequest.where(id: doomed.id)).not_to exist
      expect(File.exist?(doomed_file)).to be false

      expect(ReportRequest.where(id: kept.id)).to exist
      expect(File.exist?(kept_file)).to be true
      expect(File.read(kept_file)).to eq("pdf-bytes")
    end

    it "leaves a request sitting exactly ON the boundary alone" do
      on_boundary = aged_request(age: 30.days.ago + 1.minute)

      post path, params: { days_old: 30 }.to_json, headers: service_headers

      expect(ReportRequest.where(id: on_boundary.id)).to exist
    end

    it "never deletes an in-flight request, however old" do
      pending_old = aged_request(age: 400.days.ago, status: "pending")
      processing_old = aged_request(age: 400.days.ago, status: "processing")

      post path, params: { days_old: 30 }.to_json, headers: service_headers

      expect(ReportRequest.where(id: [pending_old.id, processing_old.id]).count).to eq(2)
    end

    # For a destructive sweep the safe direction to fail is toward MORE
    # retention. Every rejected days_old falls back to the 30-day DEFAULT, not
    # to the 1-day floor — a floor fallback would delete nearly everything.
    it "falls back to the default retention window for a zero-day request" do
      today = create(:report_request, account: internal_account, status: "completed")
      week_old = aged_request(age: 7.days.ago)

      post path, params: { days_old: 0 }.to_json, headers: service_headers

      expect(ReportRequest.where(id: [today.id, week_old.id]).count).to eq(2)
      expect(JSON.parse(response.body).dig("data", "days_old"))
        .to eq(Api::V1::Internal::ReportsController::DEFAULT_RETENTION_DAYS)
    end

    it "falls back to the default retention window for an unparseable request" do
      week_old = aged_request(age: 7.days.ago)

      post path, params: { days_old: "abc" }.to_json, headers: service_headers

      expect(ReportRequest.where(id: week_old.id)).to exist
      expect(JSON.parse(response.body).dig("data", "days_old"))
        .to eq(Api::V1::Internal::ReportsController::DEFAULT_RETENTION_DAYS)
    end

    it "falls back to the default retention window for an absurdly large request" do
      post path, params: { days_old: 1_000_000_000 }.to_json, headers: service_headers

      expect(JSON.parse(response.body).dig("data", "days_old"))
        .to eq(Api::V1::Internal::ReportsController::DEFAULT_RETENTION_DAYS)
    end

    it "counts without deleting when dry_run is set" do
      old = aged_request(age: 90.days.ago)

      post path, params: { days_old: 30, dry_run: true }.to_json, headers: service_headers

      body = JSON.parse(response.body)
      expect(body.dig("data", "candidate_count")).to eq(1)
      expect(body.dig("data", "deleted_count")).to eq(0)
      expect(ReportRequest.where(id: old.id)).to exist
    end

    it "bounds a single pass and reports the remaining backlog" do
      3.times { aged_request(age: 90.days.ago) }

      post path, params: { days_old: 30, limit: 2 }.to_json, headers: service_headers

      body = JSON.parse(response.body)
      expect(body.dig("data", "candidate_count")).to eq(3)
      expect(body.dig("data", "deleted_count")).to eq(2)
      expect(body.dig("data", "remaining_count")).to eq(1)
      expect(ReportRequest.count).to eq(1)
    end

    it "records an audit entry naming each destroyed request" do
      doomed = aged_request(age: 90.days.ago)

      expect {
        post path, params: { days_old: 30 }.to_json, headers: service_headers
      }.to change { AuditLog.where(action: "report_request_cleanup_deleted").count }.by(1)

      entry = AuditLog.where(action: "report_request_cleanup_deleted").order(:created_at).last
      expect(entry.resource_id).to eq(doomed.id)
      expect(entry.account_id).to eq(doomed.account_id)
    end

    it "records no deletion audit entry for a dry run" do
      aged_request(age: 90.days.ago)

      expect {
        post path, params: { days_old: 30, dry_run: true }.to_json, headers: service_headers
      }.not_to change { AuditLog.where(action: "report_request_cleanup_deleted").count }
    end

    it "does not leak the destroyed row identities into the response body" do
      aged_request(age: 90.days.ago)

      post path, params: { days_old: 30 }.to_json, headers: service_headers

      expect(JSON.parse(response.body)["data"]).not_to have_key("deleted_records")
    end
  end
end
