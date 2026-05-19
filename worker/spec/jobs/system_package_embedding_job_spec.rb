# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec. SystemPackageEmbeddingJob loops over
# /packages/process_embedding_batch until remaining: 0, holding a 3h per-repo
# Redis lock. Spec covers: single-batch completion, multi-batch loop, lock
# already held.
RSpec.describe SystemPackageEmbeddingJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:repository_id) { "repo-#{SecureRandom.hex(4)}" }
  let(:job_args) { repository_id }
  let(:api_client) { instance_spy(BackendApiClient) }
  let(:lock_key) { "system:pkg:embed:#{repository_id}" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    Sidekiq.redis { |c| c.del(lock_key) }
  end

  after do
    Sidekiq.redis { |c| c.del(lock_key) }
  end

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/packages/process_embedding_batch" }

    context "single batch completes the work (remaining: 0)" do
      let(:response) { { "data" => { "processed" => 23, "remaining" => 0, "errors" => [] } } }

      before do
        allow(api_client).to receive(:post).with(endpoint, any_args).and_return(response)
      end

      it "POSTs the batch endpoint at least once" do
        job.execute(repository_id)
        expect(api_client).to have_received(:post).with(endpoint, any_args).at_least(:once)
      end

      it "returns a Hash summary" do
        result = job.execute(repository_id)
        expect(result).to be_a(Hash)
      end

      it "releases the lock" do
        job.execute(repository_id)
        expect(Sidekiq.redis { |c| c.get(lock_key) }).to be_nil
      end
    end

    context "multi-batch: two calls until remaining: 0" do
      it "POSTs the batch endpoint multiple times" do
        responses = [
          { "data" => { "processed" => 50, "remaining" => 10, "errors" => [] } },
          { "data" => { "processed" => 10, "remaining" => 0,  "errors" => [] } }
        ]
        allow(api_client).to receive(:post).with(endpoint, any_args)
          .and_return(*responses)
        job.execute(repository_id)
        expect(api_client).to have_received(:post).with(endpoint, any_args).at_least(2).times
      end
    end

    context "when the per-repo lock is already held" do
      before do
        Sidekiq.redis { |c| c.set(lock_key, Time.current.to_f, ex: 60) }
      end

      it "skips without calling the API" do
        result = job.execute(repository_id)
        expect(result).to include(skipped: true)
        expect(api_client).not_to have_received(:post)
      end
    end
  end
end
