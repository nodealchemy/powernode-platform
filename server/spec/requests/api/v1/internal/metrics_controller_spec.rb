# frozen_string_literal: true

require "rails_helper"

# IMP-3515f2ebc25a + D10 — the Rails API runs no in-process Sidekiq, so the real
# fleet job-processing metrics come from the worker's Sidekiq via its HTTP API.
# When the worker is reachable the endpoint proxies its live stats; when it is
# NOT, it reports an honest available:false + the server's ActiveJob adapter,
# never a fabricated 100% success_rate.
RSpec.describe "Api::V1::Internal::Metrics#jobs", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_service_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  def fetch_job_metrics
    post "/api/v1/internal/metrics/jobs", headers: worker_service_headers, as: :json
    response
  end

  it "requires worker mTLS authentication" do
    post "/api/v1/internal/metrics/jobs"
    expect(response).to have_http_status(:unauthorized)
  end

  context "when the worker is unreachable" do
    before { allow(WorkerJobService).to receive(:fetch_sidekiq_stats).and_raise(WorkerJobService::WorkerServiceError) }

    it "reports available:false + the server adapter, never a fabricated healthy stat" do
      fetch_job_metrics
      expect(response).to have_http_status(:ok)
      metrics = JSON.parse(response.body).dig("data", "job_metrics")

      expect(metrics["available"]).to be(false)
      expect(metrics["adapter"]).to eq(ActiveJob::Base.queue_adapter_name)
      expect(metrics["success_rate"]).to be_nil
      expect(metrics["success_rate"]).not_to eq(100.0)
    end
  end

  context "when the worker returns live Sidekiq stats" do
    before do
      allow(WorkerJobService).to receive(:fetch_sidekiq_stats).and_return(
        "processed" => 90, "failed" => 10, "enqueued" => 3,
        "scheduled_size" => 2, "retry_size" => 1, "dead_size" => 0,
        "workers_size" => 4, "default_queue_latency" => 0.5,
        "queues" => { "default" => { "size" => 3, "latency" => 0.5 } },
        "timestamp" => "2026-06-26T00:00:00Z"
      )
    end

    it "proxies the worker's real job metrics" do
      fetch_job_metrics
      metrics = JSON.parse(response.body).dig("data", "job_metrics")

      expect(metrics["available"]).to be(true)
      expect(metrics["source"]).to eq("worker_sidekiq")
      expect(metrics["processed"]).to eq(90)
      expect(metrics["failed"]).to eq(10)
      expect(metrics["workers"]).to eq(4)
      expect(metrics["queues"]).to eq("default" => { "size" => 3, "latency" => 0.5 })
      # 90 / (90+10) = 90.0 — a real computed rate, not a fabricated constant.
      expect(metrics["success_rate"]).to eq(90.0)
    end
  end
end
