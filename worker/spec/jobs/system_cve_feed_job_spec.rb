# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec. SystemCveFeedJob uses a Redis SET-NX
# concurrency lock (CONCURRENCY_LOCK key, 600s TTL) to prevent overlapping
# hourly NVD pulls. Spec covers: happy ingest, API error path, lock-already-held.
RSpec.describe SystemCveFeedJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  # instance_spy (not instance_double) so 'not_to have_received(:post)' works
  # in the lock-already-held context where no post is expected.
  let(:api_client) { instance_spy(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    Sidekiq.redis { |c| c.del(described_class::CONCURRENCY_LOCK) }
  end

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/cve/ingest" }

    context "when no other instance holds the lock" do
      let(:response) do
        { "data" => { "ingested_count" => 7, "updated_count" => 2, "exposures_updated" => 12 } }
      end

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "returns the counts from the server payload" do
        result = job.execute
        expect(result).to include(ok: true, ingested: 7, updated: 2, exposures_updated: 12)
      end

      it "releases the lock on completion" do
        job.execute
        held = Sidekiq.redis { |c| c.exists(described_class::CONCURRENCY_LOCK) }
        expect(held).to eq(0)
      end
    end

    context "when the lock is already held by another instance" do
      before do
        Sidekiq.redis { |c| c.set(described_class::CONCURRENCY_LOCK, "held", ex: 60) }
      end

      it "skips without calling the API" do
        result = job.execute
        expect(result).to include(skipped: true)
        expect(api_client).not_to have_received(:post)
      ensure
        Sidekiq.redis { |c| c.del(described_class::CONCURRENCY_LOCK) }
      end
    end

    context "when the API errors" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_raise(BackendApiClient::ApiError.new("nvd unreachable"))
      end

      it "returns ok: false and releases the lock" do
        result = job.execute
        expect(result).to include(ok: false)
        expect(result[:error]).to match(/nvd unreachable/)
        held = Sidekiq.redis { |c| c.exists(described_class::CONCURRENCY_LOCK) }
        expect(held).to eq(0)
      end
    end
  end
end
