# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260928000000_close_stale_completed_campaign_loops.rb")

# IMP-3e36e30d5c72. See the migration file's own comment for the full rationale
# (in particular why this reimplements CampaignDriver's closing rule with raw
# column writes rather than calling any app model code).
RSpec.describe CloseStaleCompletedCampaignLoops do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }

  before { allow(migration).to receive(:say) }

  it "completes a running loop under a completed campaign whose tasks are all passed or skipped" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t2", status: "skipped")

    migration.up

    loop.reload
    expect(loop.status).to eq("completed")
    expect(loop.completed_at).to be_present
    expect(loop.configuration["final_result"]).to eq("reason" => "backfill_imp_3e36e30d5c72")
  end

  it "cancels a running loop under a completed campaign that has leftover work, keeping its tasks" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t2", status: "pending")

    migration.up

    loop.reload
    expect(loop.status).to eq("cancelled")
    expect(loop.configuration["cancellation_reason"]).to include("IMP-3e36e30d5c72")
    expect(loop.ralph_tasks.pluck(:task_key, :status)).to contain_exactly(%w[t1 passed], %w[t2 pending])
  end

  it "does not touch a running loop under an ACTIVE campaign (negative fixture)" do
    campaign = create(:ai_campaign, account: account, status: "active")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    migration.up

    expect(loop.reload.status).to eq("running")
  end

  it "does not touch a running loop with NO campaign (negative fixture)" do
    loop = create(:ai_ralph_loop, account: account, campaign: nil, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    migration.up

    expect(loop.reload.status).to eq("running")
  end

  it "does not touch a PENDING loop under a completed campaign (negative fixture — status filter is 'running' only)" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "pending")

    migration.up

    expect(loop.reload.status).to eq("pending")
  end

  # IMP-3e36e30d5c72 (review round, item 1): RalphLoop#complete! does not raise on a
  # repeating task — it logs a warning and returns early, leaving the row non-terminal.
  # A naive "call complete!" here would leave the loop running forever, same bug. The
  # operator's direction is that every touched loop ends terminal, so this becomes
  # cancelled instead, with a reason that names the repeating task.
  it "cancels (never leaves running) a loop that would otherwise complete but has a repeating task" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed", repeating: true)

    migration.up

    loop.reload
    expect(loop.status).to eq("cancelled")
    expect(loop.configuration["cancellation_reason"]).to include("repeating task")
  end

  it "recomputes updated_at, duration_ms, and total/completed/failed task counts the same way RalphLoop's own callbacks would" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    started_at = 2.hours.ago
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running",
                                  started_at: started_at, updated_at: 3.hours.ago)
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t2", status: "failed")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t3", status: "pending")

    migration.up

    loop.reload
    expect(loop.status).to eq("cancelled") # t3 pending is leftover work
    expect(loop.total_tasks).to eq(3)
    expect(loop.completed_tasks).to eq(1)
    expect(loop.failed_tasks).to eq(1)
    expect(loop.updated_at).to be_within(5.seconds).of(Time.current)
    expect(loop.duration_ms).to eq(((loop.completed_at - started_at) * 1000).to_i)
  end

  it "does not set duration_ms when started_at is blank, matching RalphLoop#calculate_duration's own guard" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running", started_at: nil)
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    migration.up

    expect(loop.reload.duration_ms).to be_nil
  end

  it "is a no-op on a second run — an already-closed loop is no longer selected" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    migration.up
    completed_at = loop.reload.completed_at

    migration.up
    loop.reload
    expect(loop.status).to eq("completed")
    expect(loop.completed_at).to eq(completed_at)
  end

  it "refuses to run down: which rows it touched and their prior task tallies cannot be reconstructed" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
