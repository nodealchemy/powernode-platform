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

    # G2: acceptance-rate floor (anti-churn) — applies to BOTH runtimes.
    context "acceptance-rate floor" do
      def lands!(landed:, rejected:)
        create_list(:ai_campaign_land, landed, :landed, campaign: campaign, account: account) if landed.positive?
        create_list(:ai_campaign_land, rejected, :rejected, campaign: campaign, account: account) if rejected.positive?
      end

      it "stops once enough attempts have landed below the floor" do
        campaign.update!(status: "active", stop_conditions: { "min_acceptance_pct" => 50, "min_acceptance_sample" => 4 })
        lands!(landed: 1, rejected: 3) # 25% over 4 attempts
        expect(campaign.should_stop?).to be true
      end

      it "keeps going while at or above the floor" do
        campaign.update!(status: "active", stop_conditions: { "min_acceptance_pct" => 50, "min_acceptance_sample" => 4 })
        lands!(landed: 3, rejected: 1) # 75%
        expect(campaign.should_stop?).to be false
      end

      it "does not stop before the minimum sample of attempts (young campaign)" do
        campaign.update!(status: "active", stop_conditions: { "min_acceptance_pct" => 50, "min_acceptance_sample" => 4 })
        lands!(landed: 0, rejected: 2) # 0% but only 2 attempts < sample
        expect(campaign.should_stop?).to be false
      end

      it "is inert when no floor is configured" do
        campaign.update!(status: "active", stop_conditions: {})
        lands!(landed: 0, rejected: 5)
        expect(campaign.should_stop?).to be false
      end
    end

    # G2: cost-per-accepted-change DOLLAR budget — METERED (platform-driven) loops ONLY.
    # Flat-rate CLI loops spend no platform $, so this stop must never halt them.
    context "cost-per-accepted-change budget (metered only)" do
      let(:campaign) { create(:ai_campaign, :active, account: account) }

      # A platform-driven (metered) loop with `cost` of iteration spend.
      def metered_loop_with_cost(cost)
        loop_rec = create(:ai_ralph_loop, account: account, campaign: campaign, driver_kind: "platform_agent")
        create(:ai_ralph_iteration, ralph_loop: loop_rec, cost: cost)
        loop_rec
      end

      it "stops a metered campaign whose cost-per-accepted-change exceeds the budget" do
        campaign.update!(stop_conditions: { "max_cost_per_accepted_change" => 5.0 })
        metered_loop_with_cost(12.0)
        create(:ai_campaign_land, :landed, campaign: campaign, account: account) # 12.0 / 1 = 12.0 > 5.0
        expect(campaign.should_stop?).to be true
      end

      it "keeps going when cost-per-accepted-change is at or below the budget" do
        campaign.update!(stop_conditions: { "max_cost_per_accepted_change" => 5.0 })
        metered_loop_with_cost(8.0)
        create_list(:ai_campaign_land, 2, :landed, campaign: campaign, account: account) # 8.0 / 2 = 4.0 <= 5.0
        expect(campaign.should_stop?).to be false
      end

      it "does NOT stop a flat-rate (claude_code) campaign over the same threshold (scoping proof)" do
        campaign.update!(stop_conditions: { "max_cost_per_accepted_change" => 5.0 })
        flat = create(:ai_ralph_loop, account: account, campaign: campaign, driver_kind: "claude_code")
        create(:ai_ralph_iteration, ralph_loop: flat, cost: 100.0) # flat-rate spend is uncapped
        create(:ai_campaign_land, :landed, campaign: campaign, account: account)
        expect(campaign.should_stop?).to be false
      end

      it "does not stop before any change has landed (no non-zero denominator)" do
        campaign.update!(stop_conditions: { "max_cost_per_accepted_change" => 5.0 })
        metered_loop_with_cost(50.0) # spend exists, but nothing accepted yet
        expect(campaign.should_stop?).to be false
      end

      it "is inert when no budget is configured" do
        campaign.update!(stop_conditions: {})
        metered_loop_with_cost(50.0)
        create(:ai_campaign_land, :landed, campaign: campaign, account: account)
        expect(campaign.should_stop?).to be false
      end
    end
  end

  describe "#acceptance_pct (G2)" do
    it "is nil with no terminal land attempts" do
      create(:ai_campaign_land, campaign: campaign, account: account) # pending_approval, not terminal
      expect(campaign.acceptance_pct).to be_nil
    end

    it "computes landed over terminal attempts" do
      create_list(:ai_campaign_land, 3, :landed, campaign: campaign, account: account)
      create(:ai_campaign_land, :rejected, campaign: campaign, account: account)
      expect(campaign.acceptance_pct).to eq(75.0)
    end

    it "excludes non-terminal (parked / in-flight) lands from the denominator" do
      create(:ai_campaign_land, :landed, campaign: campaign, account: account)
      create(:ai_campaign_land, :rejected, campaign: campaign, account: account)
      create(:ai_campaign_land, :parked, campaign: campaign, account: account)
      create(:ai_campaign_land, campaign: campaign, account: account) # pending_approval
      expect(campaign.acceptance_pct).to eq(50.0)
    end

    it "counts failed and rolled_back as non-accepted attempts" do
      create(:ai_campaign_land, :landed, campaign: campaign, account: account)
      create(:ai_campaign_land, :failed, campaign: campaign, account: account)
      create(:ai_campaign_land, :rolled_back, campaign: campaign, account: account)
      expect(campaign.acceptance_pct).to be_within(0.01).of(33.33)
    end
  end

  describe "#cost_per_accepted_change (G2, metered loops only)" do
    let(:campaign) { create(:ai_campaign, :active, account: account) }

    def metered_loop_with_cost(cost)
      loop_rec = create(:ai_ralph_loop, account: account, campaign: campaign, driver_kind: "platform_agent")
      create(:ai_ralph_iteration, ralph_loop: loop_rec, cost: cost)
      loop_rec
    end

    it "is nil when the campaign has no metered (platform-driven) loops" do
      create(:ai_ralph_loop, account: account, campaign: campaign, driver_kind: "claude_code")
      create(:ai_campaign_land, :landed, campaign: campaign, account: account)
      expect(campaign.cost_per_accepted_change).to be_nil
    end

    it "is nil when there are no accepted lands yet" do
      metered_loop_with_cost(5.0)
      expect(campaign.cost_per_accepted_change).to be_nil
    end

    it "divides metered iteration spend by accepted lands" do
      metered_loop_with_cost(6.0)
      metered_loop_with_cost(4.0) # total metered spend 10.0
      create_list(:ai_campaign_land, 2, :landed, campaign: campaign, account: account)
      expect(campaign.cost_per_accepted_change).to eq(5.0) # 10.0 / 2
    end

    it "excludes flat-rate (claude_code) loop cost from the metered spend" do
      metered_loop_with_cost(8.0)
      flat = create(:ai_ralph_loop, account: account, campaign: campaign, driver_kind: "claude_code")
      create(:ai_ralph_iteration, ralph_loop: flat, cost: 100.0) # must NOT count
      create(:ai_campaign_land, :landed, campaign: campaign, account: account)
      expect(campaign.cost_per_accepted_change).to eq(8.0)
    end
  end

  describe "#summary surfaces the G2 metrics" do
    it "includes acceptance_pct and cost_per_accepted_change" do
      create_list(:ai_campaign_land, 2, :landed, campaign: campaign, account: account)
      create(:ai_campaign_land, :rejected, campaign: campaign, account: account)
      s = campaign.summary
      expect(s).to have_key(:acceptance_pct)
      expect(s).to have_key(:cost_per_accepted_change)
      expect(s[:acceptance_pct]).to be_within(0.01).of(66.67)
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

    # Bug: a completion_pct target self-finalized the campaign on the FIRST passed
    # increment (an unseeded loop reads 1/1 = 100%) while the loop was still draining.
    # The pct-stop must be gated on loop terminality.
    it "does NOT finalize on a 100% completion_pct target while a loop is still active" do
      loop_rec = create(:ai_ralph_loop, account: campaign.account, campaign: campaign, status: "running")
      create(:ai_ralph_task, ralph_loop: loop_rec, status: "passed") # 1/1 = 100% so far
      campaign.update!(stop_conditions: { "completion_pct" => 100 })
      campaign.snapshot_progress!

      expect(campaign.completion_pct).to eq(100.0)
      expect(campaign.should_stop?).to be false
      expect { campaign.maybe_finalize! }.not_to(change { campaign.reload.status })
      expect(campaign.status).to eq("active")
    end

    it "lets the completion_pct target finalize once the loop has gone terminal" do
      loop_rec = create(:ai_ralph_loop, account: campaign.account, campaign: campaign, status: "running")
      create(:ai_ralph_task, ralph_loop: loop_rec, status: "passed")
      campaign.update!(stop_conditions: { "completion_pct" => 100 })
      campaign.snapshot_progress!
      expect(campaign.should_stop?).to be false

      loop_rec.update!(status: "completed")
      expect(campaign.should_stop?).to be true
      expect { campaign.maybe_finalize! }.to change { campaign.reload.status }.from("active").to("completed")
    end
  end
end
