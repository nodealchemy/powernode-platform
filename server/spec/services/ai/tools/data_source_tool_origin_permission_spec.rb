# frozen_string_literal: true

require "rails_helper"

# MCP identity plan #7: DataSourceTool#permission? by door.
#   * an internal call                 -> allowed
#   * an agent call                    -> the account-wide check, unchanged here
#   * a call a door marked, no agent   -> the call's own user must hold the grant
#                                         (fails closed on a nil user, and when the
#                                          permission read itself raises)
#   * no mark and no agent             -> allowed: a REST controller authorized it
# Every example asserts the row, not only the envelope.
RSpec.describe Ai::Tools::DataSourceTool, "mutation permission by door (MCP identity plan #7)" do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) } # first user: OWNER, holds every permission
  let(:reader) { create(:user, account: account, permissions: %w[ai.data_sources.read]) }
  let(:updater) { create(:user, account: account, permissions: %w[ai.data_sources.read ai.data_sources.update]) }
  let!(:data_source) do
    create(:ai_data_source, account: account, slug: "open-meteo", source_type: "open_meteo", name: "Before")
  end

  def tool_for(user: nil, agent: nil, internal: false, origin: nil)
    tool = described_class.new(account: account, user: user, agent: agent, internal: internal)
    tool.call_origin = origin if origin
    tool
  end

  def update!(tool)
    tool.execute(params: { action: "data_source_update", data_source_id: data_source.id, name: "After" }
                          .with_indifferent_access)
  end

  it "refuses a marked call with no agent whose own user lacks the grant, from every tool door" do
    Ai::Tools::CallOrigin::ALL.each do |origin|
      result = update!(tool_for(user: reader, origin: origin))

      expect(result[:success]).to be(false), "#{origin} was let through"
      expect(result[:error]).to include("ai.data_sources.update")
    end
    expect(data_source.reload.name).to eq("Before")
  end

  it "fails closed for a marked call that carries no user" do
    expect(tool_for(origin: "mcp_instance").send(:permission?, "ai.data_sources.update")).to be(false)
  end

  it "lets a marked call through when its own user holds the grant" do
    result = update!(tool_for(user: updater, origin: "mcp_oauth"))

    expect(result[:success]).to be(true), result[:error].to_s
    expect(data_source.reload.name).to eq("After")
  end

  it "refuses a marked call whose permission read raises, at the arm and end to end" do
    tool = tool_for(user: updater, origin: "mcp_oauth")
    allow(updater).to receive(:has_permission?).and_raise(ActiveRecord::StatementInvalid, "permission read failed")

    expect(tool.send(:permission?, "ai.data_sources.update")).to be(false)

    result = update!(tool)

    expect(result[:success]).to be(false)
    expect(data_source.reload.name).to eq("Before")
  end

  it "control for the raise: the same marked call runs when the permission read answers" do
    tool = tool_for(user: updater, origin: "mcp_oauth")
    allow(updater).to receive(:has_permission?).and_return(true)

    expect(tool.send(:permission?, "ai.data_sources.update")).to be(true)

    result = update!(tool)

    expect(result[:success]).to be(true), result[:error].to_s
    expect(data_source.reload.name).to eq("After")
  end

  it "keeps today's rule for an unmarked call with no agent (a REST door authorized it)" do
    result = update!(tool_for(user: reader))

    expect(result[:success]).to be(true), result[:error].to_s
    expect(data_source.reload.name).to eq("After")
  end

  it "keeps the account-wide check for an agent call" do
    agent = create(:ai_agent, account: account, creator: owner)

    result = update!(tool_for(user: reader, agent: agent, origin: "agent_bridge"))

    expect(result[:success]).to be(true), result[:error].to_s
    expect(data_source.reload.name).to eq("After")
  end

  it "lets an internal call through" do
    expect(tool_for(internal: true, origin: "skill_recipe").send(:permission?, "ai.data_sources.update")).to be(true)
  end
end
