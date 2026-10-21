# frozen_string_literal: true

require "rails_helper"

# Round-3 L-1: a skill executor a tool builds is a step of the same call. It
# inherits the call's door and its driver, and on a stand-in door (the agent
# bridge) the driver is explicitly unknown, never the creator the call runs as.
RSpec.describe Ai::Tools::BaseTool, "#build_skill_executor driver propagation" do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
  let(:runner) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: creator) }

  let(:executor_class) do
    Class.new do
      attr_reader :user
      attr_accessor :driving_user, :parent_call_origin

      def initialize(account:, agent: nil, user: nil)
        @user = user
      end
    end
  end

  let(:tool_class) do
    Class.new(described_class) do
      def self.definition = { name: "spec_tool", description: "spec", parameters: {} }
      def build(klass) = build_skill_executor(klass)
    end
  end

  def tool(origin:)
    tool_class.new(account: account, user: creator, agent: agent).tap { |t| t.call_origin = origin }
  end

  it "passes an explicit nil driver on the agent-bridge door" do
    executor = tool(origin: Ai::Tools::CallOrigin::AGENT_BRIDGE).build(executor_class)
    expect(executor.user).to eq(creator)
    expect(executor.instance_variable_defined?(:@driving_user)).to be(true)
    expect(executor.driving_user).to be_nil
    expect(executor.parent_call_origin).to eq(Ai::Tools::CallOrigin::AGENT_BRIDGE)
  end

  it "passes the real driver the bridge named" do
    t = tool(origin: Ai::Tools::CallOrigin::AGENT_BRIDGE)
    t.driving_user = runner
    expect(t.build(executor_class).driving_user).to eq(runner)
  end

  it "passes the tool's user as driver on a door whose user is real" do
    origin = Ai::Tools::CallOrigin::ALL.find { |o| o != Ai::Tools::CallOrigin::AGENT_BRIDGE }
    executor = tool(origin: origin).build(executor_class)
    expect(executor.driving_user).to eq(creator)
    expect(executor.parent_call_origin).to eq(origin)
  end
end
