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
                "region_count" => 3, "synced_count" => 12, "updated_count" => 4,
                "held_count" => 2, "guest_lost_count" => 1, "ambiguous_count" => 0,
                "terminated_guest_present" => [ "inst-1" ] },
              { "account_id" => "acct-2", "ok" => true,
                "region_count" => 1, "synced_count" => 5, "updated_count" => 0,
                "held_count" => 0, "guest_lost_count" => 0, "ambiguous_count" => 1,
                "terminated_guest_present" => [] }
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

      # IMP-ff6d46f2c3e1: these were previously dropped on the floor here —
      # aggregated by the controller, never read on this side. NOT the fix
      # for gap (1) (that is System::Fleet::Sensors::TerminatedGuestPresentSensor,
      # entirely server-side); this is closing the literal omission the
      # finding named in the one place a human might still be reading.
      it "aggregates the held/guest-lost/ambiguous/terminated-guest-present counts across accounts" do
        result = job.execute

        expect(result).to include(
          held_count: 2,
          guest_lost_count: 1,
          ambiguous_count: 1,
          terminated_guest_present_count: 1
        )
      end

      # ABSENCE HAS A MODE: a response that never mentions these keys at all
      # (an older/degraded controller response, or every region reporting a
      # clean tick with the keys omitted rather than zeroed) must still sum
      # to an explicit 0, never a missing key — the log line's shape must not
      # change between "measured zero" and "field absent from the payload".
      it "reports an explicit zero, never an omitted key, when a result omits these fields entirely" do
        allow(api_client).to receive(:post)
          .with("/api/v1/system/worker_api/cloud_sync/reconcile", {})
          .and_return("data" => { "tick_count" => 1,
                                  "results" => [ { "account_id" => "acct-1", "ok" => true,
                                                   "region_count" => 1, "synced_count" => 1,
                                                   "updated_count" => 0 } ] })

        result = job.execute

        expect(result).to include(
          held_count: 0,
          guest_lost_count: 0,
          ambiguous_count: 0,
          terminated_guest_present_count: 0
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
