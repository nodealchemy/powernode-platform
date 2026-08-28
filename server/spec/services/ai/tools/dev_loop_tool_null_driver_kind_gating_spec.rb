# frozen_string_literal: true

require "rails_helper"

# Regression cover for the fail-open `driver_kind.blank?` short-circuit.
#
# `delegation_block_reason` (dev_loop_tool.rb) and `platform_drain_blocked?`
# (internal/ai/ralph_loops_controller.rb) both treated a NULL driver_kind on a
# CAMPAIGN loop as "legacy => ungated" and returned early, skipping the
# single-driver lease check entirely. Two drivers could then drain one campaign.
#
# The branch was vacuous when found: CampaignDriver#create_campaign_loop is the
# sole creation path for campaign loops and always sets driver_kind
# ("nil would mean legacy — campaigns are explicit"), and production held zero
# campaign loops. These examples force the NULL state directly so the gate is
# pinned fail-closed rather than relying on the producer staying well-behaved.
RSpec.describe Ai::Tools::DevLoopTool, "campaign loop with NULL driver_kind" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:cdriver) { Ai::DevLoop::CampaignDriver.new(account: account, user: user) }
  let(:campaign) { cdriver.start(name: "NullDriverKind")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  before do
    # Bypass validation deliberately: no supported code path produces this row,
    # which is precisely why the guard must not assume it cannot exist.
    loop_record.update_columns(driver_kind: nil)
  end

  def pull(holder: nil)
    params = { action: "dev_next_task", loop_id: loop_record.id }
    params[:holder] = holder if holder
    tool.execute(params: params.with_indifferent_access)
  end

  it "is still blocked when another driver holds the campaign lease" do
    campaign.acquire_driver_lease!(holder: "other-sess")

    res = pull(holder: "cc-1")

    expect(res[:halted]).to be true
    expect(res[:reason]).to eq("leased_to:other-sess")
  end

  it "is still blocked for a holder-less caller while the lease is held" do
    campaign.acquire_driver_lease!(holder: "other-sess")

    res = pull

    expect(res[:halted]).to be true
    expect(res[:reason]).to eq("leased_to:other-sess")
  end

  it "still lets the lease-holding caller through" do
    res = pull(holder: "cc-1")

    expect(res[:halted]).to be_falsey
    expect(campaign.reload.driver_lease_holder).to eq("cc-1")
  end
end
