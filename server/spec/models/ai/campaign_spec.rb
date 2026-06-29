# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Campaign, type: :model do
  let(:account) { create(:account) }
  let(:campaign) { create(:ai_campaign, account: account) }

  describe "lifecycle" do
    it "moves created -> active -> paused -> active -> completed" do
      expect(campaign.status).to eq("created")
      campaign.start!
      expect(campaign.status).to eq("active")
      expect(campaign.started_at).to be_present
      campaign.pause!("operator review")
      expect(campaign.status).to eq("paused")
      expect(campaign.paused_reason).to eq("operator review")
      campaign.resume!
      expect(campaign.status).to eq("active")
      campaign.complete!("all done")
      expect(campaign.status).to eq("completed")
      expect(campaign).to be_terminal
      expect(campaign.completion_summary).to eq("all done")
    end

    it "validates status + decision_authority" do
      expect(build(:ai_campaign, status: "bogus")).not_to be_valid
      expect(build(:ai_campaign, decision_authority: "godmode")).not_to be_valid
    end
  end

  describe "#park_question! and answering" do
    it "queues an open question, exposes it, and counts it" do
      q = campaign.park_question!(question: "Stripe vs PayPal for payouts?", context: "F3 fork")
      expect(q.status).to eq("open")
      expect(campaign.open_questions_list).to include(q)
      expect(campaign.reload.open_questions).to eq(1)
    end

    it "answering closes it and decrements the open count" do
      user = create(:user, account: account)
      q = campaign.park_question!(question: "Pricing policy?")
      expect(q.answer!("first 100 free per month", user: user)).to be true
      expect(q.reload.status).to eq("answered")
      expect(q.answer).to eq("first 100 free per month")
      expect(campaign.reload.open_questions).to eq(0)
    end
  end

  describe "#record_decision!" do
    it "logs a typed decision" do
      d = campaign.record_decision!(decision_type: "remove", title: "drop dead async vertical",
                                    rationale: "zero callers")
      expect(d.decision_type).to eq("remove")
      expect(campaign.campaign_decisions.recent).to include(d)
    end
  end

  describe "#snapshot_progress! roll-up across driven loops" do
    it "aggregates task counts, persists a ledger entry, and updates denormalized counters" do
      loop = create(:ai_ralph_loop, account: account, campaign: campaign)
      create(:ai_ralph_task, ralph_loop: loop, status: "passed")
      create(:ai_ralph_task, ralph_loop: loop, status: "passed")
      create(:ai_ralph_task, ralph_loop: loop, status: "failed")
      create(:ai_ralph_task, ralph_loop: loop, status: "blocked")
      create(:ai_ralph_task, ralph_loop: loop, status: "pending")

      entry = campaign.snapshot_progress!

      expect(entry.total_tasks).to eq(5)
      expect(entry.completed_tasks).to eq(2)
      expect(entry.failed_tasks).to eq(1)
      expect(entry.blocked_tasks).to eq(1)
      expect(entry.completion_pct).to eq(40.0)
      expect(entry.per_loop_summary[loop.id]).to be_present

      expect(campaign.reload.loop_count).to eq(1)
      expect(campaign.total_tasks).to eq(5)
      expect(campaign.completed_tasks).to eq(2)
      expect(campaign.completion_pct).to eq(40.0)
    end
  end

  describe "single-driver lease" do
    it "acquires when free and reports the lease as active" do
      expect(campaign.driver_lease_active?).to be false
      expect(campaign.acquire_driver_lease!(holder: "sess-a")).to be true
      expect(campaign.reload.driver_lease_active?).to be true
      expect(campaign.driver_lease_info).to include(holder: "sess-a")
    end

    it "refuses a second holder while a lease is active, but lets the holder renew" do
      campaign.acquire_driver_lease!(holder: "sess-a", ttl: 30.minutes)
      first_expiry = campaign.reload.driver_lease_expires_at

      expect(campaign.acquire_driver_lease!(holder: "sess-b")).to be false
      expect(campaign.reload.driver_lease_holder).to eq("sess-a")

      expect(campaign.acquire_driver_lease!(holder: "sess-a", ttl: 60.minutes)).to be true
      expect(campaign.reload.driver_lease_expires_at).to be > first_expiry
    end

    it "lets a new holder acquire once the prior lease has expired" do
      campaign.acquire_driver_lease!(holder: "sess-a", ttl: 30.minutes)
      campaign.update_columns(driver_lease_expires_at: 1.minute.ago)

      expect(campaign.driver_lease_active?).to be false
      expect(campaign.acquire_driver_lease!(holder: "sess-b")).to be true
      expect(campaign.reload.driver_lease_holder).to eq("sess-b")
    end

    it "only the holder (or no-one) may release; a non-holder release is a no-op" do
      campaign.acquire_driver_lease!(holder: "sess-a")
      expect(campaign.release_driver_lease!(holder: "sess-b")).to be false
      expect(campaign.reload.driver_lease_holder).to eq("sess-a")

      expect(campaign.release_driver_lease!(holder: "sess-a")).to be true
      expect(campaign.reload.driver_lease_holder).to be_nil
      expect(campaign.driver_lease_active?).to be false
    end

    it "requires a holder to acquire" do
      expect { campaign.acquire_driver_lease!(holder: "") }.to raise_error(ArgumentError)
    end

    it "exposes the lease in #summary" do
      campaign.acquire_driver_lease!(holder: "sess-a")
      expect(campaign.reload.summary[:driver_lease]).to include(holder: "sess-a")
    end
  end

  describe "#should_stop?" do
    it "stops on a terminal status" do
      campaign.complete!
      expect(campaign.should_stop?).to be true
    end

    it "stops when failed_tasks hits the configured max" do
      campaign.update!(status: "active", stop_conditions: { "max_failed" => 2 }, failed_tasks: 2)
      expect(campaign.should_stop?).to be true
    end

    it "keeps going below the thresholds" do
      campaign.update!(status: "active", stop_conditions: { "max_failed" => 5 }, failed_tasks: 1)
      expect(campaign.should_stop?).to be false
    end
  end

  describe "#maybe_finalize! (terminal finalization)" do
    let(:campaign) { create(:ai_campaign, :active) }

    def drained_loop_with_task!(loop_status: "completed", task_status: "passed")
      loop_rec = create(:ai_ralph_loop, account: campaign.account, campaign: campaign, status: loop_status)
      create(:ai_ralph_task, ralph_loop: loop_rec, status: task_status)
      loop_rec
    end

    it "completes when a stop condition (completion_pct target) is met" do
      campaign.update!(stop_conditions: { "completion_pct" => 100 }, total_tasks: 2, completed_tasks: 2)
      expect { campaign.maybe_finalize! }.to change { campaign.reload.status }.from("active").to("completed")
    end

    it "completes when fully drained: loops ended, tasks terminal, no open questions" do
      drained_loop_with_task!
      expect { campaign.maybe_finalize! }.to change { campaign.reload.status }.to("completed")
      expect(campaign.completed_at).to be_present
    end

    it "does NOT finalize while a loop is still active" do
      drained_loop_with_task!(loop_status: "running")
      expect { campaign.maybe_finalize! }.not_to(change { campaign.reload.status })
      expect(campaign.status).to eq("active")
    end

    it "does NOT finalize while a question is open" do
      drained_loop_with_task!
      campaign.park_question!(question: "needs operator input")
      expect { campaign.maybe_finalize! }.not_to(change { campaign.reload.status })
    end

    it "does NOT finalize a campaign with no tasks (nothing ran)" do
      create(:ai_ralph_loop, account: campaign.account, campaign: campaign, status: "completed")
      expect { campaign.maybe_finalize! }.not_to(change { campaign.reload.status })
    end

    it "is idempotent once terminal" do
      campaign.update!(status: "completed")
      expect { campaign.maybe_finalize! }.not_to(change { campaign.reload.status })
    end
  end
end
