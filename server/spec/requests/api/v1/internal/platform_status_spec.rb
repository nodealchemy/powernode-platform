# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — the worker→server door.
RSpec.describe "Api::V1::Internal platform status sweep", type: :request do
  let(:account) { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  # stub_const needs the controller's constant name; naming it once keeps the
  # examples from repeating a long literal that would silently stop matching
  # if the class moved.
  def described_class_for_controller
    "Api::V1::Internal::PlatformStatusController"
  end

  def post_sweep(params = {}, headers: worker_headers)
    post "/api/v1/internal/platform/status_sweep",
         params: params.to_json,
         headers: headers.merge("Content-Type" => "application/json")
  end

  describe "authentication" do
    it "refuses a request with no worker mTLS identity" do
      post_sweep({}, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts the worker's mTLS identity — the other arm" do
      system_worker

      post_sweep

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/internal/platform/status_sweep" do
    it "runs the runner for the named account and reports its summary" do
      system_worker
      allow(Platform::Status::SweepRunner).to receive(:run!).and_call_original

      post_sweep({ account_id: account.id })

      expect(Platform::Status::SweepRunner).to have_received(:run!).with(account).once
      body = JSON.parse(response.body)["data"]
      expect(body["accounts_swept"]).to eq(1)
      expect(body["summaries"].first["account_id"]).to eq(account.id)
    end

    it "sweeps every account when none is named" do
      system_worker
      other = create(:account)

      post_sweep

      ids = JSON.parse(response.body)["data"]["summaries"].map { |s| s["account_id"] }
      expect(ids).to include(account.id, other.id)
    end

    it "surfaces a skipped account with its reason rather than hiding it as a success" do
      system_worker
      account.suspend_ai!

      post_sweep({ account_id: account.id })

      summary = JSON.parse(response.body)["data"]["summaries"].first
      expect(summary["skipped"]).to be(true)
      expect(summary["reason"]).to eq("kill_switch")
    end

    it "reports one account's failure without losing the others" do
      system_worker
      other = create(:account)
      allow(Platform::Status::SweepRunner).to receive(:run!) do |acct|
        raise "sweep exploded" if acct.id == account.id

        { skipped: false, transitions: [], events_written: 0, reaped: 0, kinds: {} }
      end

      post_sweep

      expect(response).to have_http_status(:ok)
      summaries = JSON.parse(response.body)["data"]["summaries"].index_by { |s| s["account_id"] }
      expect(summaries[account.id]["error"]).to include("sweep exploded")
      expect(summaries[other.id]["skipped"]).to be(false)
    end

    it "prunes expired events ONCE per request and reports how many went" do
      system_worker
      old_event = create(:platform_status_event, account: account, occurred_at: 60.days.ago)
      kept = create(:platform_status_event, account: account, occurred_at: 1.hour.ago)
      # Two accounts, so a per-account prune would show up as a double count.
      create(:account)

      post_sweep

      expect(JSON.parse(response.body)["data"]["events_pruned"]).to eq(1)
      expect(Platform::StatusEvent.exists?(old_event.id)).to be(false)
      expect(Platform::StatusEvent.exists?(kept.id)).to be(true)
    end

    it "does NOT prune on a standby plane" do
      system_worker
      old_event = create(:platform_status_event, account: account, occurred_at: 60.days.ago)
      allow(::Platform::Status::SweepRunner).to receive(:control_plane_active?).and_return(false)

      post_sweep

      expect(JSON.parse(response.body)["data"]["events_pruned"]).to eq(0)
      expect(Platform::StatusEvent.exists?(old_event.id)).to be(true)
    end

    it "still reports a successful sweep when retention itself fails" do
      system_worker
      allow(::Platform::Status::EventRetention).to receive(:prune!).and_raise("retention exploded")

      post_sweep

      # Housekeeping that fails must not turn a successful sweep into a failed
      # request; the next tick tries again.
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["events_pruned"]).to eq(0)
    end

    # A2 review M1 — the ceiling had NO oracle: deleting it entirely left the
    # request spec green, so the whole truncation mechanism was unexecuted code.
    describe "the wall-clock ceiling" do
      it "TRUNCATES once the ceiling is passed, and names the accounts it did not reach" do
        system_worker
        3.times { create(:account) }
        stub_const("#{described_class_for_controller}::MAX_SWEEP_SECONDS", 0)

        post_sweep

        body = JSON.parse(response.body)["data"]
        expect(response).to have_http_status(:ok)
        expect(body["truncated"]).to be(true)
        # Zero accounts started: the ceiling is checked BEFORE each account.
        expect(body["accounts_swept"]).to be < ::Account.count
        expect(body["unswept"]["count"]).to be > 0
      end

      it "reports nothing unswept when the sweep finishes inside the ceiling — the other arm" do
        system_worker
        create(:account)

        post_sweep

        body = JSON.parse(response.body)["data"]
        expect(body["truncated"]).to be(false)
        expect(body["unswept"]).to eq("count" => 0, "first_id" => nil)
      end
    end

    # A2 review M2 — a systematic overrun must not starve the same tail forever.
    describe "the rotating cursor" do
      it "starts AFTER the cursor and wraps, so a truncated tick's tail is swept first next time" do
        system_worker
        accounts = [ account, create(:account), create(:account) ].sort_by(&:id)
        # Stands in for "the previous tick got as far as accounts.first".
        ::Platform::Status::SweepCursor.write(accounts.first.id)

        post_sweep

        order = JSON.parse(response.body)["data"]["summaries"].map { |s| s["account_id"] }
        # The two the previous tick never reached come FIRST; the one it did
        # reach wraps to the end. A fixed starting point would sweep
        # accounts.first again and starve the tail on every tick forever.
        expect(order).to eq([ accounts[1].id, accounts[2].id, accounts[0].id ])
      end

      it "starts from the top with no cursor — the other arm" do
        system_worker
        accounts = [ account, create(:account) ].sort_by(&:id)
        ::Platform::Status::SweepCursor.clear

        post_sweep

        order = JSON.parse(response.body)["data"]["summaries"].map { |s| s["account_id"] }
        expect(order).to eq(accounts.map(&:id))
      end

      it "clears the cursor when a tick finishes the whole set, so the next starts from the top" do
        system_worker
        ::Platform::Status::SweepCursor.write("some-earlier-id")

        post_sweep

        expect(::Platform::Status::SweepCursor.read).to be_nil
      end
    end

    # A2 review M5 — the single-producer guarantee belongs to the door.
    describe "the per-account lock" do
      it "SKIPS an account another caller is already sweeping, writing no events" do
        system_worker
        allow(::Platform::Status::AccountLock).to receive(:try_acquire!).and_return(false)

        post_sweep({ account_id: account.id })

        summary = JSON.parse(response.body)["data"]["summaries"].first
        expect(summary["skipped"]).to be(true)
        expect(summary["reason"]).to eq("locked")
        expect(Platform::StatusEvent.count).to eq(0)
      end

      it "sweeps normally when the lock is free — the other arm" do
        system_worker
        allow(::Platform::Status::AccountLock).to receive(:try_acquire!).and_call_original

        post_sweep({ account_id: account.id })

        summary = JSON.parse(response.body)["data"]["summaries"].first
        expect(summary["reason"]).to be_nil
        expect(summary["skipped"]).to be(false)
      end
    end

    it "reports truncated: false on a sweep that finished inside its ceiling" do
      system_worker

      post_sweep

      expect(JSON.parse(response.body)["data"]["truncated"]).to be(false)
    end
  end
end
