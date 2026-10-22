# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec.
RSpec.describe SystemFleetReconcileJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_double(BackendApiClient) }

  # The lock is a real Redis key, shared by every process on the same Redis
  # database (another spec process, a dev worker ticking the real fleet). A
  # per-example key keeps one holder's lock from turning another's tick into
  # a skip.
  before do
    stub_const("#{described_class}::CONCURRENCY_LOCK",
               "#{described_class::CONCURRENCY_LOCK}:spec:#{SecureRandom.hex(8)}")
    allow(job).to receive(:api_client).and_return(api_client)
  end

  after { Sidekiq.redis { |c| c.del(described_class::CONCURRENCY_LOCK) } }

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/fleet/reconcile" }

    context "happy path" do
      let(:response) { { "data" => { "sensed_signals" => 5, "actions_taken" => 1 } } }

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "POSTs the reconcile endpoint" do
        result = job.execute
        expect(result).to be_a(Hash)
        expect(result).not_to include(:error)
        expect(api_client).to have_received(:post).with(endpoint, {})
      end
    end

    context "when another tick holds the lock" do
      before { Sidekiq.redis { |c| c.set(described_class::CONCURRENCY_LOCK, "held", ex: 60) } }

      it "skips without posting and leaves the other tick's lock in place" do
        expect(api_client).not_to receive(:post)

        expect(job.execute).to include(skipped: true)
        expect(Sidekiq.redis { |c| c.get(described_class::CONCURRENCY_LOCK) }).to eq("held")
      end
    end

    # Two runs interleaved: the second starts while the first is inside its
    # API call. The second must skip, and its exit must not release the
    # first's lock; the first's own exit then releases it.
    context "when a second run starts while the first holds the lock" do
      let(:second_job) { described_class.new }
      let(:second_api_client) { instance_double(BackendApiClient) }

      it "skips the second run and leaves the lock with the first until the first finishes" do
        allow(second_job).to receive(:api_client).and_return(second_api_client)
        expect(second_api_client).not_to receive(:post)
        lock_value = -> { Sidekiq.redis { |c| c.get(described_class::CONCURRENCY_LOCK) } }
        observed = {}

        allow(api_client).to receive(:post).with(endpoint, {}) do
          observed[:held_by_first] = lock_value.call
          observed[:second_result] = second_job.execute
          observed[:after_second] = lock_value.call
          { "data" => {} }
        end

        job.execute

        expect(observed[:held_by_first]).to be_present
        expect(observed[:second_result]).to include(skipped: true)
        expect(observed[:after_second]).to eq(observed[:held_by_first]),
          "the skipped second run released the lock the first run still held"
        expect(lock_value.call).to be_nil
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_raise(BackendApiClient::ApiError.new("server down"))
      end

      it "returns ok: false" do
        expect(job.execute).to include(ok: false)
      end
    end
  end
end
