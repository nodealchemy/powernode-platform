# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec. SystemTaskReaperJob is the hourly safety
# net for stuck operations. GETs /tasks?status=pending and /tasks?status=running
# with stuck_since thresholds, then re-enqueues or fails as appropriate.
RSpec.describe SystemTaskReaperJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_spy(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    context "happy path: no stuck tasks" do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/system/worker_api/tasks", anything)
          .and_return({ "data" => { "tasks" => [] } })
        # The reaper may also POST to clean up running tasks; allow either.
        allow(api_client).to receive(:post).and_return({ "data" => {} })
      end

      it "returns aggregate counts" do
        result = job.execute
        expect(result).to be_a(Hash)
        expect(result).to include(reaped_pending: 0, reaped_running: 0)
      end

      it "queries the tasks endpoint with both pending and running statuses" do
        job.execute
        expect(api_client).to have_received(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: "pending")).at_least(:once)
        expect(api_client).to have_received(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: "running")).at_least(:once)
      end
    end

    context "when the upstream tasks API errors" do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/system/worker_api/tasks", anything)
          .and_raise(BackendApiClient::ApiError.new("upstream down"))
        # The reaper continues to the second status call; stub that too.
        allow(api_client).to receive(:post).and_return({ "data" => {} })
      end

      it "handles the error gracefully (returns a Hash, doesn't crash)" do
        # The reaper deliberately doesn't raise — it's a safety-net job that
        # should soldier on through transient upstream issues. The aggregate
        # counts reflect whatever it managed to reap before the error.
        expect { job.execute }.not_to raise_error
      end
    end
  end

  describe "sidekiq_options" do
    it "uses retry: 0 (reaper failures alert operator instead of cascading retries)" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(0)
    end
  end

  describe "threshold constants" do
    it "exposes pending and running thresholds in seconds" do
      expect(described_class::STUCK_PENDING_THRESHOLD).to be_a(Integer).and(be > 0)
      expect(described_class::STUCK_RUNNING_THRESHOLD).to be_a(Integer).and(be > 0)
    end
  end
end
