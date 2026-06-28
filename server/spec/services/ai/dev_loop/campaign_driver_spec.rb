# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:driver) { described_class.new(account: account, user: user) }

  describe "#start" do
    it "creates an active campaign with a dedicated campaign-scoped Ralph loop + first snapshot" do
      result = driver.start(name: "Improve billing", decision_authority: "trusted",
                            configuration: { "scope" => { "trees" => ["server/app"] } })
      campaign = result[:campaign]
      loop = result[:loop]

      expect(campaign).to be_persisted
      expect(campaign.status).to eq("active")
      expect(campaign.decision_authority).to eq("trusted")
      expect(campaign.created_by_id).to eq(user.id)
      expect(loop.campaign_id).to eq(campaign.id)
      expect(loop.branch).to eq("campaign/#{campaign.id}")
      expect(loop.configuration["workload"]).to eq("improvement-campaign")
      expect(campaign.progress_entries.count).to eq(1)
    end
  end

  describe "#status" do
    it "returns the campaign summary, open questions, recent decisions, and loops" do
      campaign = driver.start(name: "X")[:campaign]
      campaign.park_question!(question: "Free-tier pricing policy?")
      campaign.record_decision!(decision_type: "remove", title: "drop dead code")

      st = driver.status(campaign)
      expect(st[:campaign][:name]).to eq("X")
      expect(st[:open_questions].size).to eq(1)
      expect(st[:recent_decisions].size).to eq(1)
      expect(st[:loops].size).to eq(1)
    end
  end

  describe "#claim / #release (single-driver lease)" do
    it "claims a free campaign, blocks a second driver, and frees it on release" do
      campaign = driver.start(name: "X")[:campaign]
      other = described_class.new(account: account, user: create(:user, account: account))

      first = driver.claim(campaign, holder: "sess-a")
      expect(first[:ok]).to be true
      expect(first[:lease]).to include(holder: "sess-a")

      blocked = other.claim(campaign, holder: "sess-b")
      expect(blocked[:ok]).to be false
      expect(blocked[:held_by]).to eq("sess-a")

      expect(driver.release(campaign, holder: "sess-a")).to eq({ ok: true })
      expect(other.claim(campaign, holder: "sess-b")[:ok]).to be true
    end

    it "defaults the holder to the driver's user id" do
      campaign = driver.start(name: "X")[:campaign]
      res = driver.claim(campaign)
      expect(res[:ok]).to be true
      expect(campaign.reload.driver_lease_holder).to eq(user.id.to_s)
    end
  end

  describe "#answer_question" do
    it "answers a parked question and clears the open count" do
      campaign = driver.start(name: "X")[:campaign]
      q = campaign.park_question!(question: "Stripe or PayPal for payouts?")

      res = driver.answer_question(campaign, question_id: q.id, answer: "Stripe Connect")
      expect(res[:status]).to eq("answered")
      expect(res[:answer]).to eq("Stripe Connect")
      expect(campaign.reload.open_questions).to eq(0)
    end
  end

  describe "#stop" do
    it "pauses the campaign's loops and marks it completed" do
      campaign = driver.start(name: "X")[:campaign]
      driver.stop(campaign, summary: "shipped")

      expect(campaign.reload.status).to eq("completed")
      expect(campaign.completion_summary).to eq("shipped")
      expect(campaign.ralph_loops.first.reload.schedule_paused).to be true
    end
  end
end
