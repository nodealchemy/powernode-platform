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

    it "seeds a default acceptance-rate floor (G2) when the caller sets none" do
      campaign = driver.start(name: "Defaults")[:campaign]
      expect(campaign.stop_conditions["min_acceptance_pct"]).to eq(50)
    end

    it "lets a caller-supplied stop condition override the default floor" do
      campaign = driver.start(name: "Override", stop_conditions: { "min_acceptance_pct" => 80, "max_failed" => 3 })[:campaign]
      expect(campaign.stop_conditions["min_acceptance_pct"]).to eq(80)
      expect(campaign.stop_conditions["max_failed"]).to eq(3)
    end

    context "plan_increments seeding" do
      it "seeds one pending task per planned increment so total_tasks reflects the plan" do
        result = driver.start(
          name: "Planned",
          configuration: { "plan_increments" => ["First thing", { "title" => "Second thing", "description" => "do B" }] }
        )
        campaign = result[:campaign]
        loop = result[:loop]

        expect(loop.ralph_tasks.where(status: "pending").count).to eq(2)
        expect(loop.ralph_tasks.pluck(:task_key)).to contain_exactly("increment-first-thing", "increment-second-thing")
        expect(loop.ralph_tasks.find_by(task_key: "increment-second-thing").description).to eq("do B")
        expect(campaign.reload.total_tasks).to eq(2)
        expect(campaign.completion_pct).to eq(0.0)
      end

      it "honors an explicit task_key and disambiguates duplicate keys within the plan" do
        loop = driver.start(
          name: "Keys",
          configuration: { "plan_increments" => [{ "title" => "Custom", "task_key" => "kx" }, "Dup", "Dup"] }
        )[:loop]
        expect(loop.ralph_tasks.pluck(:task_key)).to contain_exactly("kx", "increment-dup", "increment-dup-2")
      end

      it "seeds no tasks when plan_increments is absent (unchanged behavior)" do
        loop = driver.start(name: "Bare")[:loop]
        expect(loop.ralph_tasks.count).to eq(0)
      end

      it "a passed first increment on a 15-plan campaign reads ~6.7%, not 100%, and does not finalize while active" do
        increments = (1..15).map { |n| "Increment #{n}" }
        campaign = driver.start(
          name: "Fifteen",
          configuration: { "plan_increments" => increments },
          stop_conditions: { "completion_pct" => 100 }
        )[:campaign]

        driver.record_increment!(campaign, title: "Increment 1")

        campaign.reload
        expect(campaign.total_tasks).to eq(15)
        expect(campaign.completed_tasks).to eq(1)
        expect(campaign.completion_pct).to be_within(0.01).of(6.67)
        expect(campaign.status).to eq("active")
      end
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
