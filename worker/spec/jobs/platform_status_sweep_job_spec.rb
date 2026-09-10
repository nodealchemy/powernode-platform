# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — the worker side.
#
# All the decisions live on the server (which accounts, which gates, what the
# reap threshold is), so this job's whole contract is: hold a lock, call once,
# report totals.
#
# THE LOCK IS EXERCISED FOR REAL, against Redis, following
# system_cve_feed_job_spec. That is what caught the DistributedLock defect
# this job was the first ever caller to hit (never-released lock under the
# Sidekiq 8 client; fixed in the concern, with its own spec). Stubbing
# `with_lock` would have tested the call site and left the mechanism
# unexecuted — which is exactly how a lock that never unlocks ships green.
RSpec.describe PlatformStatusSweepJob, type: :job do
  let(:api_client) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }
  let(:redis_key) { "lock:#{described_class::LOCK_KEY}" }

  let(:server_response) do
    {
      "data" => {
        "accounts_swept" => 2,
        "truncated" => false,
        "duration_seconds" => 0.4,
        "summaries" => [
          { "account_id" => "a1", "skipped" => false, "transitions" => 3, "events_written" => 4 },
          { "account_id" => "a2", "skipped" => true, "reason" => "kill_switch",
            "transitions" => 0, "events_written" => 0 }
        ]
      }
    }
  end

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_warn)
    Sidekiq.redis { |c| c.del(redis_key) }
  end

  after { Sidekiq.redis { |c| c.del(redis_key) } }

  it "takes the lock, calls the server's sweep endpoint exactly once, and reports the totals" do
    allow(api_client).to receive(:post)
      .with(described_class::SWEEP_PATH, {})
      .and_return(server_response)

    result = job.execute

    expect(api_client).to have_received(:post).with(described_class::SWEEP_PATH, {}).once
    expect(result).to eq(
      accounts_swept: 2,
      accounts_skipped: 1,
      transitions: 3,
      events_written: 4,
      truncated: false
    )
  end

  it "RELEASES the lock afterwards, so the next tick is not blocked by the previous one" do
    allow(api_client).to receive(:post).and_return(server_response)

    job.execute

    expect(Sidekiq.redis { |c| c.exists(redis_key) }).to eq(0)
  end

  it "releases the lock even when the sweep call raises" do
    allow(api_client).to receive(:post).and_raise(BackendApiClient::ApiError.new("backend down"))

    expect { job.execute }.to raise_error(BackendApiClient::ApiError)
    expect(Sidekiq.redis { |c| c.exists(redis_key) }).to eq(0)
  end

  it "SKIPS without calling the server when the lock is already held" do
    Sidekiq.redis { |c| c.set(redis_key, "someone-else", ex: 60) }
    allow(api_client).to receive(:post)

    result = job.execute

    expect(result).to eq(skipped: true, reason: "lock_held")
    expect(api_client).not_to have_received(:post)
    # And it did NOT steal a lock it does not own.
    expect(Sidekiq.redis { |c| c.get(redis_key) }).to eq("someone-else")
  end

  it "sets the lock TTL from the constant rather than leaving it unbounded" do
    ttl_during_run = nil
    allow(api_client).to receive(:post) do
      ttl_during_run = Sidekiq.redis { |c| c.ttl(redis_key) }
      server_response
    end

    job.execute

    expect(ttl_during_run).to be_between(described_class::LOCK_TTL_SECONDS - 5,
                                         described_class::LOCK_TTL_SECONDS)
  end

  it "warns rather than reporting a clean success when the server truncated the sweep" do
    truncated = server_response.deep_dup
    truncated["data"]["truncated"] = true
    allow(api_client).to receive(:post).and_return(truncated)

    result = job.execute

    expect(result[:truncated]).to be(true)
    expect(job).to have_received(:log_warn).with(/truncated/)
  end

  it "reserves a TTL well above the cron period so a slow sweep is not raced by its own lock" do
    # 60s cron, 240s TTL. A TTL at or near the period would expire under a
    # running holder and re-admit the pile-up the lock exists to prevent.
    expect(described_class::LOCK_TTL_SECONDS).to eq(240)
    expect(described_class::LOCK_KEY).to eq("platform:status:sweep:lock")
  end
end
