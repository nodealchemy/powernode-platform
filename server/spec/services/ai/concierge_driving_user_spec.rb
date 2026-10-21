# frozen_string_literal: true

require "rails_helper"

# Round-3 M-1 / L-2: a concierge's `user` is who it acts for; its
# `driving_user` is the person who actually drove this turn. From a REST
# session they are the same person; from a tool door whose `user` is a
# stand-in (the agent bridge runs as agent.creator) the driver is unknown.
# Only the driver reaches the bridges, for promotion grants.
RSpec.describe Ai::ConciergeService, "driving user" do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
  let(:concierge) { create(:ai_agent, account: account, creator: creator, is_concierge: true) }
  let(:conversation) { create(:ai_conversation, account: account, user: creator, agent: concierge) }

  def capture_bridge_driver
    seen = :not_built
    allow(Ai::AgentToolBridgeService).to receive(:new).and_wrap_original do |m, **kw|
      seen = kw.fetch(:driving_user, :missing)
      m.call(**kw)
    end
    allow_any_instance_of(Ai::AgentToolBridgeService).to receive(:dispatch_tool_call).and_return("{}")
    -> { seen }
  end

  it "hands the bridge the explicit driver, not the acting user" do
    seen = capture_bridge_driver
    described_class.new(conversation: conversation, user: creator, driving_user: nil)
                   .handle_confirmed_action("tool_call", { "_tool_name" => "list_agents" })
    expect(seen.call).to be_nil
  end

  it "defaults the driver to nil when none is given (fail closed)" do
    seen = capture_bridge_driver
    described_class.new(conversation: conversation, user: creator)
                   .handle_confirmed_action("tool_call", { "_tool_name" => "list_agents" })
    expect(seen.call).to be_nil
  end

  it "passes a REST driver through" do
    seen = capture_bridge_driver
    described_class.new(conversation: conversation, user: creator, driving_user: creator)
                   .handle_confirmed_action("tool_call", { "_tool_name" => "list_agents" })
    expect(seen.call).to eq(creator)
  end

  describe Ai::ConciergeToolBridge do
    it "passes driving_user to the base bridge" do
      bridge = described_class.new(agent: concierge, account: account, conversation: conversation, user: creator,
                                   driving_user: creator)
      expect(bridge.instance_variable_get(:@driving_user)).to eq(creator)
    end

    it "defaults to no driver" do
      bridge = described_class.new(agent: concierge, account: account, conversation: conversation, user: creator)
      expect(bridge.instance_variable_get(:@driving_user)).to be_nil
    end
  end

  describe "the conversation tool on the agent-bridge door" do
    it "builds the concierge with no driver (its user is the creator stand-in)" do
      seen = nil
      allow(described_class).to receive(:new).and_wrap_original do |m, **kw|
        seen = kw
        m.call(**kw)
      end
      allow_any_instance_of(described_class).to receive(:handle_confirmed_action)
      tool = Ai::Tools::ConversationTool.new(account: account, user: creator, agent: concierge)
      tool.call_origin = Ai::Tools::CallOrigin::AGENT_BRIDGE
      tool.send(:confirm_concierge_action, { conversation_id: conversation.id, action_type: "x",
                                             action_params: { "a" => 1 } }.with_indifferent_access)

      expect(seen).to include(user: creator, driving_user: nil)
    end

    it "builds it with its user as driver on a door whose user is real (MCP OAuth)" do
      seen = nil
      allow(described_class).to receive(:new).and_wrap_original do |m, **kw|
        seen = kw
        m.call(**kw)
      end
      allow_any_instance_of(described_class).to receive(:handle_confirmed_action)
      tool = Ai::Tools::ConversationTool.new(account: account, user: creator, agent: concierge)
      tool.call_origin = Ai::Tools::CallOrigin::ALL.find { |o| o != Ai::Tools::CallOrigin::AGENT_BRIDGE }
      tool.send(:confirm_concierge_action, { conversation_id: conversation.id, action_type: "x",
                                             action_params: { "a" => 1 } }.with_indifferent_access)

      expect(seen).to include(driving_user: creator)
    end
  end
end
