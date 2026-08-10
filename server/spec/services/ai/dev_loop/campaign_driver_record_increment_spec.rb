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
      # Verified evidence required for checks_passed since IMP-aa8a2f58e01e.
      result = driver.record_increment!(campaign, title: "Increment 1", summary: "did it",
                                        metadata: { "commit" => "abc1234" },
                                        check_results: { "rspec" => "12 examples, 0 failures" })
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

    # IMP-aa8a2f58e01e — this seam hardcoded checks_passed true for any passed
    # increment; it now adjudicates evidence with the same vocabulary as the
    # dev-loop bridge. Unlike the bridge it does not REJECT contradicted
    # increments (this is history recording; the revert metric backstops) —
    # but nothing unverified may record as a verified check.
    it "records an unevidenced pass as attested (checks_passed false)" do
      driver.record_increment!(campaign, title: "NoEv", task_key: "noev")
      iter = campaign.ralph_loops.first.ralph_iterations.last
      expect(iter.checks_passed).to be(false)
      expect(iter.status).to eq("completed")
    end

    it "records checks_passed false when the evidence contradicts the pass" do
      driver.record_increment!(campaign, title: "Bad", task_key: "bad",
                               check_results: { "rspec" => "12 examples, 3 failures" })
      iter = campaign.ralph_loops.first.ralph_iterations.last
      expect(iter.checks_passed).to be(false)
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

  describe "seeded-plan closeout (campaign must not linger at status=active/100%)" do
    let(:seeded) do
      driver.start(name: "seeded",
                   configuration: { "plan_increments" => [ "Slice A", "Slice B" ] })[:campaign]
    end

    it "seeds all_tasks_terminal completion criteria on the loop (goal-driven terminator applies)" do
      loop_ = seeded.ralph_loops.first
      expect(loop_.configuration["completion"]).to eq("all_tasks_terminal" => true)
    end

    it "does NOT seed completion criteria on an unseeded campaign (open-ended stays open-ended)" do
      expect(campaign.ralph_loops.first.configuration["completion"]).to be_nil
    end

    it "starts the pending loop on the first recorded increment" do
      driver.record_increment!(seeded, title: "Slice A")
      expect(seeded.ralph_loops.first.reload).to have_attributes(status: "running", started_at: be_present)
    end

    it "stays active while the seeded plan is only partially drained" do
      driver.record_increment!(seeded, title: "Slice A")
      expect(seeded.ralph_loops.first.reload.status).not_to eq("completed")
      expect(seeded.reload.status).to eq("active")
    end

    it "completes the loop AND finalizes the campaign when the seeded plan fully drains" do
      driver.record_increment!(seeded, title: "Slice A")
      driver.record_increment!(seeded, title: "Slice B")

      loop_ = seeded.ralph_loops.first.reload
      expect(loop_).to have_attributes(status: "completed", completed_at: be_present)
      expect(seeded.reload).to have_attributes(status: "completed", completed_at: be_present)
      expect(seeded.completion_summary).to match(/drained|stop condition/)
    end
  end
end
