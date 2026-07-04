# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver do
  let(:account) { create(:account) }
  let(:driver) { described_class.new(account: account) }
  let(:campaign) { driver.start(name: "obs")[:campaign] }

  describe "#record_increment! (auto-record progress per run)" do
    it "records a passed RalphTask + decision and reflects 100% completion" do
      driver.record_increment!(campaign, title: "Increment 1", summary: "did the thing", rationale: "because")

      campaign.reload
      expect(campaign.total_tasks).to eq(1)
      expect(campaign.completed_tasks).to eq(1)
      expect(campaign.completion_pct).to eq(100.0)

      loop_ = campaign.ralph_loops.first
      expect(loop_.ralph_tasks.where(status: "passed").count).to eq(1)
      expect(campaign.campaign_decisions.where(decision_type: "build").count).to eq(1)
    end

    it "records a RalphIteration (fills CC-driven iteration history)" do
      result = driver.record_increment!(campaign, title: "Increment 1", summary: "did it",
                                        metadata: { "commit" => "abc1234" })
      loop_ = campaign.ralph_loops.first
      iter = loop_.ralph_iterations.order(:iteration_number).last
      expect(iter).to have_attributes(status: "completed", iteration_number: 1,
                                      git_commit_sha: "abc1234", checks_passed: true)
      expect(iter.git_branch).to eq(loop_.branch)
      expect(result[:iteration_number]).to eq(1)
    end

    it "increments iteration_number across runs (each run is a real iteration)" do
      driver.record_increment!(campaign, title: "A", task_key: "a")
      driver.record_increment!(campaign, title: "B", task_key: "b")
      expect(campaign.ralph_loops.first.ralph_iterations.pluck(:iteration_number).sort).to eq([ 1, 2 ])
    end

    it "maps a failed increment to a failed iteration" do
      driver.record_increment!(campaign, title: "Broke", task_key: "x", status: "failed")
      iter = campaign.ralph_loops.first.ralph_iterations.last
      expect(iter).to have_attributes(status: "failed", checks_passed: false)
    end

    it "is idempotent on task_key (re-recording does not double-count)" do
      driver.record_increment!(campaign, title: "Inc", task_key: "inc-1")
      driver.record_increment!(campaign, title: "Inc", task_key: "inc-1")
      expect(campaign.reload.total_tasks).to eq(1)
    end

    it "records a non-passed status (e.g. failed → failed_tasks, not completed)" do
      driver.record_increment!(campaign, title: "Broke", task_key: "x", status: "failed", decision_type: "defer")
      campaign.reload
      expect(campaign.failed_tasks).to eq(1)
      expect(campaign.completed_tasks).to eq(0)
    end

    it "does NOT force-complete the loop after a single unseeded increment (regression guard, IMP-af21b11d476c investigation)" do
      # An unseeded campaign loop is open-ended -- more record_increment! calls
      # are expected. Force-completing it the moment the current task count
      # hits zero-pending would reopen the "first passed increment reads 100%"
      # premature-finalization bug (Campaign#should_stop?'s own guard exists
      # specifically to prevent this). The loop must stay active.
      driver.record_increment!(campaign, title: "Increment 1", summary: "did the thing", rationale: "because")

      loop_ = campaign.ralph_loops.first
      expect(loop_.reload.status).not_to eq("completed")
      expect(campaign.reload.status).not_to eq("completed")
    end

    it "raises if the campaign has no loop to record against" do
      bare = account.ai_campaigns.create!(name: "bare", status: "active", decision_authority: "trusted")
      expect { driver.record_increment!(bare, title: "x") }.to raise_error(ArgumentError, /no loop/)
    end
  end
end
