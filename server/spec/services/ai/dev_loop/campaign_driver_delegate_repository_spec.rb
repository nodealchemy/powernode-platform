# frozen_string_literal: true

require "rails_helper"

# D2: campaign_delegate hands a platform driver a loop that carries the mission's
# repository, so the tool-bridge git tools (GitToolExecutor, which reads
# ralph_loop.mission.repository) can attach — and says so when they cannot.
RSpec.describe Ai::DevLoop::CampaignDriver, "#delegate repository wiring", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:driver) { described_class.new(account: account, user: user) }
  let(:campaign) { driver.start(name: "Repository wiring")[:campaign] }
  let(:loop_record) { campaign.ralph_loops.first }
  let(:agent) { create(:ai_agent, account: account) }
  # owner/name and full_name agree: the loop derives repository_full_name from the
  # clone URL (built from owner/name), and the factory's name and full_name
  # sequences drift apart once other specs in the process pass a full_name.
  let(:repository) do
    create(:git_repository, account: account, owner: "acme", name: "widgets", full_name: "acme/widgets")
  end
  let(:mission) { create(:ai_mission, account: account, created_by: user, repository: repository) }

  it "platform_agent with a mission_id wires the mission and its repository onto the loop" do
    result = driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id, mission_id: mission.id })

    loop_record.reload
    expect(result[:target]).to eq("agent_id" => agent.id, "mission_id" => mission.id)
    expect(loop_record.default_agent_id).to eq(agent.id)
    expect(loop_record.mission_id).to eq(mission.id)
    expect(loop_record.repository_url).to eq(mission.repository.clone_url)
    expect(loop_record.repository_full_name).to eq(mission.repository.full_name)
    expect(Ai::Ralph::GitToolExecutor.available?(loop_record)).to be(true)
    expect(result[:loops].first).to include(git_tools: true)
  end

  it "platform_agent without a mission reports that no git actuator is attached" do
    result = driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id })

    loop_record.reload
    expect(loop_record.mission_id).to be_nil
    expect(loop_record.repository_url).to be_nil
    expect(result[:loops].first).to include(git_tools: false)
  end

  it "refuses another account's mission and leaves the loop untouched" do
    foreign = create(:ai_mission)

    expect do
      driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id, mission_id: foreign.id })
    end.to raise_error(ArgumentError, /mission not found in this account/)

    loop_record.reload
    expect(loop_record.mission_id).to be_nil
    expect(loop_record.driver_kind).to eq("claude_code")
  end

  it "refuses a platform_agent mission that has no repository to attach" do
    research = create(:ai_mission, :research, account: account, created_by: user)

    expect do
      driver.delegate(campaign, driver_kind: "platform_agent", target: { agent_id: agent.id, mission_id: research.id })
    end.to raise_error(ArgumentError, /has no repository/)

    expect(loop_record.reload.mission_id).to be_nil
  end

  it "platform_mission wires the mission's repository onto the loop too" do
    result = driver.delegate(campaign, driver_kind: "platform_mission", target: { mission_id: mission.id })

    loop_record.reload
    expect(loop_record.mission_id).to eq(mission.id)
    expect(loop_record.repository_url).to eq(mission.repository.clone_url)
    expect(result[:loops].first).to include(git_tools: true)
  end
end
