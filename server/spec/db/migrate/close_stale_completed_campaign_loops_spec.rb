# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260928000000_close_stale_completed_campaign_loops.rb")

# IMP-3e36e30d5c72 (incident, 2026-09-28). This migration's `up` is now a no-op —
# see the migration file's own header comment for the full rationale (running its
# original body on a weeks-old loop overflowed the then-int4 duration_ms column and
# crash-looped ops-hub Rails). The backfill it used to perform is redone, under a
# later version and a widened column, in
# spec/db/migrate/close_stale_completed_campaign_loops_redo_spec.rb.
RSpec.describe CloseStaleCompletedCampaignLoops do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }

  before { allow(migration).to receive(:say) }

  it "does not touch any loop, running or otherwise, under a completed campaign" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running")
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    expect { migration.up }.not_to change { loop.reload.attributes }
  end

  it "does not raise on a loop whose started_at is weeks old (the original overflow fixture)" do
    campaign = create(:ai_campaign, account: account, status: "completed")
    loop = create(:ai_ralph_loop, account: account, campaign: campaign, status: "running",
                                  started_at: 60.days.ago)
    create(:ai_ralph_task, ralph_loop: loop, task_key: "t1", status: "passed")

    expect { migration.up }.not_to raise_error
    expect(loop.reload.status).to eq("running")
  end

  it "is a no-op down as well" do
    expect { migration.down }.not_to raise_error
  end
end
