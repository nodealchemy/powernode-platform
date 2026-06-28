# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::CampaignDriver, "#delegate" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:driver) { described_class.new(account: account, user: user) }
  let(:campaign) { driver.start(name: "Delegatable")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }

  it "campaigns are created claude_code-driven (manual scheduling)" do
    expect(loop_record.driver_kind).to eq("claude_code")
    expect(loop_record.scheduling_mode).to eq("manual")
  end

  it "delegates to claude_code and takes the single-driver lease for the holder" do
    result = driver.delegate(campaign, driver_kind: "claude_code", holder: "cc-sess-1")

    expect(result[:driver_kind]).to eq("claude_code")
    expect(result[:lease][:holder]).to eq("cc-sess-1")
    expect(campaign.reload.driver_lease_holder).to eq("cc-sess-1")
    expect(loop_record.reload.driver_kind).to eq("claude_code")
    expect(loop_record.scheduling_mode).to eq("manual")
  end

  it "delegates to a platform agent: wires the agent + makes the loop due for the scheduler" do
    agent = create(:ai_agent, account: account)

    result = driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id })

    expect(result[:driver_kind]).to eq("platform_agent")
    loop_record.reload
    expect(loop_record.driver_kind).to eq("platform_agent")
    expect(loop_record.driver_target).to eq("agent_id" => agent.id)
    expect(loop_record.default_agent_id).to eq(agent.id)
    expect(loop_record.scheduling_mode).to eq("continuous")
    expect(loop_record.status).to eq("running")
    expect(loop_record.next_scheduled_at).to be <= Time.current
    expect(Ai::RalphLoop.due_for_execution).to include(loop_record)
  end

  it "reassignment releases the current lease so the new driver can claim it" do
    driver.delegate(campaign, driver_kind: "claude_code", holder: "cc-sess-1")
    expect(campaign.reload.driver_lease_active?).to be true

    agent = create(:ai_agent, account: account)
    driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id })

    expect(campaign.reload.driver_lease_active?).to be false # CC lease released on handoff
  end

  it "rejects an unknown driver_kind" do
    expect { driver.delegate(campaign, driver_kind: "telepathy") }.to raise_error(ArgumentError)
  end
end
