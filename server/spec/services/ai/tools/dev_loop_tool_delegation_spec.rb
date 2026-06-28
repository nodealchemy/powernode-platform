# frozen_string_literal: true

require "rails_helper"

# Increment 6: the dev-loop pull queue is gated by driver_kind + the single-driver lease
# for campaign loops, so a Claude Code session and the platform executor never race on the
# same campaign. Legacy (non-campaign) loops are unaffected.
RSpec.describe Ai::Tools::DevLoopTool, "campaign delegation gating" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:cdriver) { Ai::DevLoop::CampaignDriver.new(account: account, user: user) }
  let(:campaign) { cdriver.start(name: "Drainable")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  def pull(holder: nil)
    params = { action: "dev_next_task", loop_id: loop_record.id }
    params[:holder] = holder if holder
    tool.execute(params: params.with_indifferent_access)
  end

  it "lets the lease-holding CC session pull and renews the lease" do
    res = pull(holder: "cc-1")
    expect(res[:halted]).to be_falsey
    expect(campaign.reload.driver_lease_holder).to eq("cc-1") # renewed by the pull
  end

  it "blocks a CC pull when another driver holds the lease" do
    campaign.acquire_driver_lease!(holder: "other-sess")
    res = pull(holder: "cc-1")
    expect(res[:halted]).to be true
    expect(res[:reason]).to eq("leased_to:other-sess")
  end

  it "blocks any CC pull when the loop is delegated to the platform" do
    agent = create(:ai_agent, account: account)
    cdriver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id })
    res = pull(holder: "cc-1")
    expect(res[:halted]).to be true
    expect(res[:reason]).to eq("delegated_to_platform")
  end

  it "does not gate a legacy (non-campaign) loop" do
    legacy = account.ai_ralph_loops.create!(name: "Legacy", ai_tool: "claude_code",
                                            scheduling_mode: "manual", status: "pending", branch: "main")
    res = tool.execute(params: { action: "dev_next_task", loop_id: legacy.id }.with_indifferent_access)
    expect(res[:halted]).to be_falsey
  end
end
