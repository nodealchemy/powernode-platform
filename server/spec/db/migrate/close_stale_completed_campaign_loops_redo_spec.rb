# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260928020000_close_stale_completed_campaign_loops_redo.rb")

# IMP-3e36e30d5c72. Redo of 20260928000000 (now a no-op — see that file) after
# duration_ms was widened to bigint (20260928010000). See the original migration's
# header comment for the full closing-rule rationale; this spec mirrors the original
# migration's own spec, plus the case that actually crashed prod: a multi-week-old
# started_at.
RSpec.describe CloseStaleCompletedCampaignLoopsRedo do
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

  # IMP-3e36e30d5c72 — this is the exact fixture shape that crashed prod: a loop whose
  # started_at is weeks old. Before 20260928010000 widened duration_ms to bigint, this
  # raised ActiveModel::RangeError (2.24e9 ms > int4 max 2,147,483,647). Red-first
  # against the pre-widening column, green now.
  it "computes duration_ms without overflow for a loop started weeks ago (the exact prod crash fixture)" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    started_at = 26.days.ago # > the ~24.855-day int4-milliseconds ceiling
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running",
                                  started_at: started_at)
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    expect { migration.up }.not_to raise_error

    loop.reload
    expect(loop.status).to eq("completed")
    expect(loop.duration_ms).to be > 2_147_483_647
    expect(loop.duration_ms).to eq(((loop.completed_at - started_at) * 1000).to_i)
  end
end
