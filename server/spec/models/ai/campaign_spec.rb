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
end
