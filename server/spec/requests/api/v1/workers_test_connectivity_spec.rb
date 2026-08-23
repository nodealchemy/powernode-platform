# frozen_string_literal: true

require "rails_helper"

# Behavioural coverage for IMP-e3bef4168142: POST /api/v1/workers/:id/test
# enqueued TestWorkerJob, a class that never existed in worker/ — so a
# healthy worker was ALWAYS reported unreachable (503, "Invalid job class:
# TestWorkerJob"), and the endpoint had no completion path at all even when
# enqueue succeeded (job_status stayed "enqueued" forever).
#
# These specs assert the fix BEHAVIOURALLY, not just on HTTP status:
#   - a healthy worker's test does not 503 AND a completion signal
#     (Worker#record_activity! "test_completed" + last_seen_at) actually
#     appears — asserting only 200 would also pass an implementation that
#     enqueues into the void.
#   - a genuinely unreachable worker must NOT be reported healthy, and must
#     NOT leave behind a fabricated "test_completed" activity.
RSpec.describe "Api::V1::Workers connectivity test", type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account) }
  let(:admin_headers) { auth_headers_for(admin) }
  let(:worker) { create(:worker, account: account) }

  # The physical worker service reporting back has its own worker identity
  # (see Authentication#authenticate_request's worker-JWT branch and
  # spec/requests/api/v1/worker_callback_auth_spec.rb) — not necessarily the
  # same Worker row as the one under test, mirroring how WorkerJobService
  # always talks to the single system worker regardless of which Worker
  # record initiated the check.
  let(:reporting_worker) { create(:worker, account: create(:account)) }
  let(:worker_service_headers) do
    {
      "Authorization" => "Bearer #{Security::JwtService.encode({ type: 'worker', sub: reporting_worker.id }, 5.minutes.from_now)}"
    }
  end

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
  end

  describe "a healthy worker's full connectivity-test round trip" do
    it "does not 503, and a completion signal is recorded once the job reports back" do
      # Step 1: admin triggers the test. A healthy worker accepts the enqueue.
      allow(WorkerJobService).to receive(:enqueue_test_worker_job).and_return(true)

      post "/api/v1/workers/#{worker.id}/test_worker", headers: admin_headers, as: :json

      expect(response).not_to have_http_status(:service_unavailable)
      expect_success_response
      expect(json_response_data["job_status"]).to eq("enqueued")

      # Before TestWorkerJob reports back, there is no completion evidence yet
      # — job_status "enqueued" alone is NOT proof the worker is reachable.
      expect(worker.worker_activities.where(activity_type: "test_completed")).to be_empty

      # Step 2: TestWorkerJob (running on the worker) reports its result via
      # the exact payload shape TestWorkerJob#execute builds and posts to
      # /api/v1/workers/:id/test_results.
      post "/api/v1/workers/#{worker.id}/test_results",
           params: {
             test_results: {
               test_type: "worker_connectivity_test",
               status: "passed",
               redis_check: true,
               backend_check: true,
               duration_seconds: 0.042,
               timestamp: Time.current.iso8601
             }
           },
           headers: worker_service_headers,
           as: :json

      expect(response).to have_http_status(:ok)

      # The observable completion signal: a real activity row the operator/UI
      # can read back, and an updated last_seen_at — not just a 200.
      completion = worker.worker_activities.order(:occurred_at).last
      expect(completion.activity_type).to eq("test_completed")
      expect(completion.details["status"]).to eq("passed")
      expect(worker.reload.last_seen_at).to be_present
      expect(worker.last_seen_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "a genuinely unreachable worker" do
    it "503s and never fabricates a healthy completion" do
      allow(WorkerJobService).to receive(:enqueue_test_worker_job).and_raise(
        WorkerJobService::WorkerServiceError, "Connection refused"
      )

      post "/api/v1/workers/#{worker.id}/test_worker", headers: admin_headers, as: :json

      expect(response).to have_http_status(:service_unavailable)

      # The inverse assertion the finding calls out explicitly: absence of a
      # 200 is not by itself proof the negative case is handled correctly —
      # assert directly that no "test_completed" (healthy) activity exists,
      # only the honest "error_occurred" failure record.
      expect(worker.worker_activities.where(activity_type: "test_completed")).to be_empty
      failure = worker.worker_activities.find_by(activity_type: "error_occurred")
      expect(failure).to be_present
      expect(failure.details["status"]).to eq("failed")
    end
  end
end
