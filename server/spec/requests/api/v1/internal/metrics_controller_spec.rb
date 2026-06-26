# frozen_string_literal: true

require "rails_helper"

# IMP-3515f2ebc25a — the job-processor metrics were gated on defined?(Sidekiq),
# which is permanently false in this Rails API (it runs no in-process Sidekiq;
# the worker runs the fleet jobs and the server's own ActiveJob work runs on
# solid_queue). The endpoint therefore returned empty queues + a fabricated
# 100% success_rate that read as "healthy" by construction. These pin the
# honest degradation: an explicit availability flag + the real adapter, and NO
# fake 100% success_rate.
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

  it "reports job metrics as unavailable (no in-process Sidekiq) instead of fabricated healthy stats" do
    fetch_job_metrics

    expect(response).to have_http_status(:ok)
    metrics = JSON.parse(response.body).dig("data", "job_metrics")

    # Honest signal: this process has no in-process Sidekiq.
    expect(metrics["available"]).to be(false)
    # And the actually-configured ActiveJob adapter is surfaced (test env → "test").
    expect(metrics["adapter"]).to eq(ActiveJob::Base.queue_adapter_name)
  end

  it "does NOT fabricate a 100% success_rate that reads as healthy" do
    fetch_job_metrics

    processed = JSON.parse(response.body).dig("data", "job_metrics", "processed")
    # The misleading constant is gone — success_rate is nil (not collected here),
    # never the old 100.0.
    expect(processed["success_rate"]).to be_nil
    expect(processed["success_rate"]).not_to eq(100.0)
  end
end
