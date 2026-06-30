# frozen_string_literal: true

require "rails_helper"

# Increment 6: the platform scheduler (process_scheduled) honours campaign driver routing +
# the single-driver lease, so it never drains a campaign a Claude Code session owns.
RSpec.describe "Api::V1::Internal::Ai::RalphLoops drain gating", type: :request do
  include_context "internal api auth"

  let(:cdriver) { Ai::DevLoop::CampaignDriver.new(account: internal_account) }
  let(:campaign) { cdriver.start(name: "Schedulable")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  before do
    # Isolate the gating decision from real iteration execution.
    allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:run_iteration).and_return(success: true)
  end

  def process_scheduled
    post "/api/v1/internal/ai/ralph_loops/process_scheduled", headers: service_headers
    JSON.parse(response.body)["data"]
  end

  it "skips a CC-driven campaign loop even when it is due" do
    # Force the claude_code loop to look due; the scheduler must still skip it.
    loop_record.update_columns(status: "running", next_scheduled_at: 1.minute.ago, schedule_paused: false)
    expect_any_instance_of(Ai::Ralph::ExecutionService).not_to receive(:run_iteration)

    data = process_scheduled
    expect(data["loops_skipped"]).to be >= 1
  end

  it "skips a non-Claude flat-rate CLI (external_cli) campaign loop even when it is due" do
    cdriver.delegate(campaign, driver_kind: "external_cli")
    # Force the external_cli loop to look due; the platform scheduler must still skip it.
    loop_record.reload.update_columns(status: "running", next_scheduled_at: 1.minute.ago, schedule_paused: false)
    expect_any_instance_of(Ai::Ralph::ExecutionService).not_to receive(:run_iteration)

    data = process_scheduled
    expect(data["loops_skipped"]).to be >= 1
  end

  it "drains a platform-delegated campaign loop and holds the platform lease" do
    agent = create(:ai_agent, account: internal_account)
    cdriver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id })

    data = process_scheduled
    expect(data["loops_processed"]).to be >= 1
    expect(campaign.reload.driver_lease_holder).to eq("platform-executor")
  end

  it "skips a platform-delegated loop while a CC session holds the lease" do
    agent = create(:ai_agent, account: internal_account)
    cdriver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id })
    campaign.acquire_driver_lease!(holder: "cc-session-x") # CC grabbed it mid-handoff

    expect_any_instance_of(Ai::Ralph::ExecutionService).not_to receive(:run_iteration)
    data = process_scheduled
    expect(data["loops_skipped"]).to be >= 1
    expect(campaign.reload.driver_lease_holder).to eq("cc-session-x") # unchanged
  end
end
