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

      it "queries the tasks endpoint with pending+scheduled and running statuses" do
        job.execute
        expect(api_client).to have_received(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: %w[pending scheduled])).at_least(:once)
        expect(api_client).to have_received(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: "running")).at_least(:once)
      end
    end

    context "when a scheduled task is stuck" do
      # System::Task#schedule transitions pending -> scheduled (AASM), and the
      # reaper's own comment says it covers "pending or scheduled operations
      # whose enqueue might have been missed" — but the query only ever asked
      # for status: "pending", so a stuck :scheduled task was never fetched
      # and silently stranded forever.
      let(:stuck_scheduled_task) do
        { "id" => "sched-task-1", "created_at" => 10.minutes.ago.iso8601 }
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: "pending"))
          .and_return({ "data" => { "tasks" => [] } })
        allow(api_client).to receive(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: %w[pending scheduled]))
          .and_return({ "data" => { "tasks" => [ stuck_scheduled_task ] } })
        allow(api_client).to receive(:get)
          .with("/api/v1/system/worker_api/tasks", hash_including(status: "running"))
          .and_return({ "data" => { "tasks" => [] } })
        allow(api_client).to receive(:post).and_return({ "data" => {} })
        allow(SystemExecuteTaskJob).to receive(:perform_async)
      end

      it "re-enqueues the stuck scheduled task, not just pending ones" do
        job.execute
        expect(SystemExecuteTaskJob).to have_received(:perform_async).with("sched-task-1")
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
