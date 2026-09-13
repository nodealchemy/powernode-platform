# frozen_string_literal: true

require "rails_helper"

# BaseTool.permitted?(agent:) is the agent gate (MCP identity plan, commit 4).
# It used to answer "allowed" in two places where it could not tell: an agent
# with no account to bound it, and any error raised while reading the account's
# roles. Both fail closed now. The positive control and its negative twin keep
# the account-role answer honest.
RSpec.describe Ai::Tools::BaseTool, "agent gate fails closed" do
  let(:account) { create(:account) }
  let!(:holder) { create(:user, account: account) } # first user: OWNER, holds every permission

  let(:tool_class) do
    klass = Class.new(described_class) do
      def self.definition = { name: "spec_gate_tool", description: "gate probe", parameters: {} }
    end
    klass.const_set(:REQUIRED_PERMISSION, "ai.agents.manage")
    stub_const("SpecGateTool", klass)
  end

  it "refuses an agent with no account to bound it" do
    accountless = Struct.new(:account).new(nil)

    expect(tool_class.permitted?(agent: accountless)).to be(false)
  end

  it "refuses an agent that cannot name an account at all" do
    expect(tool_class.permitted?(agent: Object.new)).to be(false)
  end

  it "refuses when reading the account's roles raises" do
    agent = create(:ai_agent, account: account)
    allow(agent.account).to receive(:users).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect(tool_class.permitted?(agent: agent)).to be(false)
  end

  it "lets an account agent through when a user in its account holds the permission (positive control)" do
    expect(tool_class.permitted?(agent: create(:ai_agent, account: account))).to be(true)
  end

  it "refuses an account agent when no user in its account holds the permission (the other arm)" do
    other = create(:account)
    create(:user, account: other, permissions: []) # explicit []: no owner grant, so nobody holds it

    expect(tool_class.permitted?(agent: create(:ai_agent, account: other))).to be(false)
  end
end
