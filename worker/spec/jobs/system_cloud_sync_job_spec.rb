# frozen_string_literal: true

require "rails_helper"

# Comprehensive stabilization sweep P2.1 — hourly cloud-state reconciliation
# worker-side job spec.
RSpec.describe SystemCloudSyncJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:lock_key) { described_class::CONCURRENCY_LOCK }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    Sidekiq.redis { |c| c.del(lock_key) }
  end

  after do
    Sidekiq.redis { |c| c.del(lock_key) }
  end

  describe "#execute" do
    context "when no concurrent run is active" do
      let(:successful_payload) do
        {
          "data" => {
            "tick_count" => 2,
            "results" => [
              { "account_id" => "acct-1", "ok" => true,
                "region_count" => 3, "synced_count" => 12, "updated_count" => 4 },
              { "account_id" => "acct-2", "ok" => true,
                "region_count" => 1, "synced_count" => 5, "updated_count" => 0 }
            ]
          }
        }
      end

      before do
        allow(api_client).to receive(:post)
          .with("/api/v1/system/worker_api/cloud_sync/reconcile", {})
          .and_return(successful_payload)
      end

      it "calls the worker_api endpoint" do
        job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/system/worker_api/cloud_sync/reconcile", {})
      end

      it "returns aggregate counts across accounts" do
        result = job.execute

        expect(result).to include(
          account_count: 2,
          region_count: 4,
          synced_count: 17,
          updated_count: 4
        )
      end

      it "releases the lock after running" do
        job.execute
        held = Sidekiq.redis { |c| c.get(lock_key) }
        expect(held).to be_nil
      end
    end

    context "when another tick is already running" do
      before do
        Sidekiq.redis { |c| c.set(lock_key, Time.current.to_f, ex: 1800) }
      end

      it "skips and returns a skip result" do
        result = job.execute

        expect(result).to eq(skipped: true, reason: "already locked")
      end

      it "does not call the API" do
        allow(api_client).to receive(:post)
        job.execute

        expect(api_client).not_to have_received(:post)
      end
    end

    context "when the API errors" do
      before do
        allow(api_client).to receive(:post)
          .and_raise(BackendApiClient::ApiError.new("503 service unavailable"))
      end

      it "logs the failure and returns a structured error" do
        result = job.execute

        expect(result).to include(ok: false)
        expect(result[:error]).to include("503")
      end

      it "still releases the lock so the next tick can run" do
        job.execute
        held = Sidekiq.redis { |c| c.get(lock_key) }
        expect(held).to be_nil
      end
    end
  end
end
