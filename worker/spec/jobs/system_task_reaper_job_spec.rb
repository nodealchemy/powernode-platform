# frozen_string_literal: true

require "rails_helper"

# SystemTaskReaperJob is the hourly safety net for stuck System tasks.
#
# It spent five weeks reporting "reap cycle complete, 0, 0" — a green log line —
# while a backlog grew, because its list endpoint was scoped through
# `System::Node.where(worker: current_worker)` and `node.worker_id` is NULL on
# every node that has ever existed. The scope was the empty set; a janitor that
# sees nothing and a clean fleet are indistinguishable from the outside.
#
# So these examples are written against the two things that were actually wrong:
# WHERE it looks (the account-scoped janitor seam, not the worker-scoped tasks
# endpoint), and WHETHER it can terminally close anything (it previously had no
# lane that could ever finish an agent-delegated task whose agent was gone).
RSpec.describe SystemTaskReaperJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_spy(BackendApiClient) }

  let(:janitor_path) { "/api/v1/system/worker_api/janitor/tasks" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(api_client).to receive(:get).and_return({ "data" => { "tasks" => [] } })
    allow(api_client).to receive(:post).and_return({ "data" => { "reaped" => true, "transition" => "cancel" } })
    allow(SystemExecuteTaskJob).to receive(:perform_async)
  end

  def task(id:, status: "pending", command: "ssh_command", age: 10.minutes,
           started_ago: nil, agent_delegated: false)
    {
      "id" => id,
      "status" => status,
      "command" => command,
      "created_at" => age.ago.iso8601,
      "started_at" => started_ago&.ago&.iso8601,
      "agent_delegated" => agent_delegated
    }
  end

  def stub_lane(status:, tasks:, older_than: nil)
    matcher = older_than ? hash_including(status: status, older_than_seconds: older_than)
                         : hash_including(status: status)
    allow(api_client).to receive(:get).with(janitor_path, matcher)
      .and_return({ "data" => { "tasks" => tasks } })
  end

  describe "where it looks" do
    # The load-bearing example. The old endpoint's scope was empty by
    # construction; querying it at all is the bug, so its absence is the
    # assertion. Without this, a revert to the worker-scoped path would go
    # unnoticed by every other example here, since they only stub the janitor.
    it "never queries the worker-scoped tasks endpoint" do
      job.execute

      expect(api_client).not_to have_received(:get).with("/api/v1/system/worker_api/tasks", anything)
      expect(api_client).not_to have_received(:post)
        .with(a_string_matching(%r{worker_api/tasks/[^/]+/fail}), anything)
    end

    it "queries the account-scoped janitor seam for every lane" do
      job.execute

      expect(api_client).to have_received(:get)
        .with(janitor_path, hash_including(status: %w[pending scheduled])).at_least(:once)
      expect(api_client).to have_received(:get)
        .with(janitor_path, hash_including(status: %w[running])).at_least(:once)
    end
  end

  describe "lane 1 — re-enqueue" do
    it "re-enqueues a stuck pending task" do
      stub_lane(status: %w[pending scheduled], tasks: [ task(id: "t-pending") ],
                older_than: described_class::STUCK_PENDING_THRESHOLD)

      expect(job.execute[:reaped_pending]).to eq(1)
      expect(SystemExecuteTaskJob).to have_received(:perform_async).with("t-pending")
    end

    # System::Task#schedule transitions pending -> scheduled, and a stuck
    # :scheduled task is exactly as re-enqueueable as a stuck :pending one.
    it "re-enqueues a stuck scheduled task, not just pending ones" do
      stub_lane(status: %w[pending scheduled],
                tasks: [ task(id: "t-sched", status: "scheduled") ],
                older_than: described_class::STUCK_PENDING_THRESHOLD)

      job.execute

      expect(SystemExecuteTaskJob).to have_received(:perform_async).with("t-sched")
    end

    # ExecutionDispatcher deliberately leaves agent-delegated tasks :pending for
    # the node agent to poll. Re-enqueuing one runs a job that declines and
    # changes nothing, so counting it as "re-enqueued" reported work that never
    # happened. Skipping keeps the count meaning "actually re-dispatched".
    it "does NOT re-enqueue an agent-delegated task" do
      stub_lane(status: %w[pending scheduled],
                tasks: [ task(id: "t-agent", command: "ci.module_build", agent_delegated: true) ],
                older_than: described_class::STUCK_PENDING_THRESHOLD)

      expect(job.execute[:reaped_pending]).to eq(0)
      expect(SystemExecuteTaskJob).not_to have_received(:perform_async)
    end

    # Past the unrunnable threshold, lane 3 owns the row. Re-enqueuing it as
    # well would fire a pointless job at something already being closed.
    it "does NOT re-enqueue a task already past the unrunnable threshold" do
      stub_lane(status: %w[pending scheduled],
                tasks: [ task(id: "t-ancient", age: 30.days) ],
                older_than: described_class::STUCK_PENDING_THRESHOLD)

      expect(job.execute[:reaped_pending]).to eq(0)
      expect(SystemExecuteTaskJob).not_to have_received(:perform_async)
    end
  end

  describe "lane 2 — fail stuck running" do
    it "reaps a running task stuck past the threshold" do
      stub_lane(status: %w[running],
                tasks: [ task(id: "t-run", status: "running", started_ago: 3.hours) ])

      expect(job.execute[:reaped_running]).to eq(1)
      expect(api_client).to have_received(:post)
        .with("#{janitor_path}/t-run/reap", hash_including(:reason))
    end

    it "leaves a freshly-started running task alone" do
      stub_lane(status: %w[running],
                tasks: [ task(id: "t-fresh", status: "running", started_ago: 1.minute) ])

      expect(job.execute[:reaped_running]).to eq(0)
      expect(api_client).not_to have_received(:post)
    end
  end

  describe "lane 3 — the terminal policy" do
    # Without this lane the queue only ever grows: an agent-delegated task whose
    # instance is gone can never be re-enqueued into completion, and nothing
    # else closes it. This is the lane that drains the backlog.
    it "reaps a pending task older than the unrunnable threshold" do
      ancient = task(id: "t-old", age: 30.days, command: "ci.module_build", agent_delegated: true)
      stub_lane(status: %w[pending scheduled], tasks: [ ancient ],
                older_than: described_class::UNRUNNABLE_THRESHOLD)

      expect(job.execute[:reaped_unrunnable]).to eq(1)
      expect(api_client).to have_received(:post).with("#{janitor_path}/t-old/reap", hash_including(:reason))
    end

    it "does not count a task the server declined to reap" do
      stub_lane(status: %w[pending scheduled], tasks: [ task(id: "t-raced", age: 30.days) ],
                older_than: described_class::UNRUNNABLE_THRESHOLD)
      allow(api_client).to receive(:post).with("#{janitor_path}/t-raced/reap", anything)
        .and_return({ "data" => { "reaped" => false, "detail" => "already terminal (complete)" } })

      expect(job.execute[:reaped_unrunnable]).to eq(0)
    end

    it "is far enough out that a node offline for a working day keeps its work" do
      expect(described_class::UNRUNNABLE_THRESHOLD).to be > 24 * 3600
    end
  end

  describe "resilience" do
    it "soldiers on when the janitor endpoint errors" do
      allow(api_client).to receive(:get).and_raise(BackendApiClient::ApiError.new("upstream down"))

      expect { job.execute }.not_to raise_error
      expect(job.execute).to include(reaped_pending: 0, reaped_running: 0, reaped_unrunnable: 0)
    end

    it "soldiers on when an individual reap errors" do
      stub_lane(status: %w[running],
                tasks: [ task(id: "t-run", status: "running", started_ago: 3.hours) ])
      allow(api_client).to receive(:post).and_raise(BackendApiClient::ApiError.new("boom"))

      expect { job.execute }.not_to raise_error
      expect(job.execute[:reaped_running]).to eq(0)
    end
  end

  describe "sidekiq_options" do
    it "uses retry: 0 (reaper failures alert operator instead of cascading retries)" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(0)
    end
  end

  describe "threshold constants" do
    it "exposes all three thresholds in seconds" do
      expect(described_class::STUCK_PENDING_THRESHOLD).to be_a(Integer).and(be > 0)
      expect(described_class::STUCK_RUNNING_THRESHOLD).to be_a(Integer).and(be > 0)
      expect(described_class::UNRUNNABLE_THRESHOLD).to be_a(Integer).and(be > 0)
    end

    it "orders them so each lane fires only after the previous has had its chance" do
      expect(described_class::STUCK_PENDING_THRESHOLD).to be < described_class::UNRUNNABLE_THRESHOLD
      expect(described_class::STUCK_RUNNING_THRESHOLD).to be < described_class::UNRUNNABLE_THRESHOLD
    end
  end
end
