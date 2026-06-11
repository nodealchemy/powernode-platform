# frozen_string_literal: true

require "rails_helper"

# Audit F5-12 — SystemComplianceSnapshotJob was the only one of the 13
# extension worker jobs without a job spec. Mirrors
# system_fleet_event_retention_job_spec / system_cloud_sync_job_spec:
# maintenance queue, Redis-locked, POSTs the worker_api archive endpoint.
RSpec.describe SystemComplianceSnapshotJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:lock_key) { described_class::CONCURRENCY_LOCK }
  let(:endpoint) { "/api/v1/system/worker_api/compliance/archive" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    Sidekiq.redis { |c| c.del(lock_key) }
  end

  after { Sidekiq.redis { |c| c.del(lock_key) } }

  describe "sidekiq_options" do
    it "uses the maintenance queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("maintenance")
    end
  end

  describe "#execute" do
    context "happy path" do
      let(:response) do
        { "data" => { "snapshots_emitted" => 7, "accounts_failed" => 0, "errors" => [] } }
      end

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "POSTs the archive endpoint and returns the aggregate summary" do
        result = job.execute

        expect(api_client).to have_received(:post).with(endpoint, {})
        expect(result).to include(snapshots_emitted: 7, accounts_failed: 0)
        expect(result[:errors]).to eq([])
      end

      it "releases the lock so a subsequent run can acquire it" do
        job.execute
        expect(Sidekiq.redis { |c| c.get(lock_key) }).to be_nil
      end

      it "logs per-account failures without failing the job" do
        allow(api_client).to receive(:post).with(endpoint, {}).and_return(
          { "data" => { "snapshots_emitted" => 5, "accounts_failed" => 1,
                        "errors" => [ { "account_id" => "acct-9", "error" => "vault down" } ] } }
        )

        result = job.execute
        expect(result[:accounts_failed]).to eq(1)
        expect(result[:errors].first["account_id"]).to eq("acct-9")
      end
    end

    context "when a concurrent run holds the lock" do
      before do
        allow(api_client).to receive(:post)
        Sidekiq.redis { |c| c.set(lock_key, Time.current.to_f, ex: 1800) }
      end

      it "skips without calling the API" do
        result = job.execute
        expect(result).to eq(skipped: true, reason: "already locked")
        expect(api_client).not_to have_received(:post)
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_raise(BackendApiClient::ApiError.new("backend 503"))
      end

      it "returns ok: false and releases the lock" do
        expect(job.execute).to include(ok: false, error: "backend 503")
        expect(Sidekiq.redis { |c| c.get(lock_key) }).to be_nil
      end
    end
  end
end
