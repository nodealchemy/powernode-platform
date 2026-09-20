# frozen_string_literal: true

require "rails_helper"

# BaseTool.permitted?(agent:) is the agent gate (MCP identity plan, commit 4).
# It used to answer "allowed" in two places where it could not tell: an agent
# with no account to bound it, and any error raised while reading the
# permission check. Both fail closed. The positive control and its negative
# twin keep the answer honest.
#
# IMP-82db8ba318aa: the account-role rung this file names is now the
# CREATOR's role, not any account user's (permitted_by_creator_role?,
# renamed from permitted_by_account_role?) — the positive/negative controls
# below assert THAT, and cover every decision this task's review made
# explicit: an inactive creator must not confer authority; neither does an
# active creator whose ACCOUNT is suspended/cancelled; a creator from a
# DIFFERENT account than the agent is refused defensively; the result is a
# strict boolean, never nil; and system.admin still short-circuits through
# unchanged (User#has_permission?'s own behavior).
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

  it "refuses when reading the creator's permission raises" do
    agent = create(:ai_agent, account: account, creator: holder)
    allow(agent.creator).to receive(:has_permission?).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect(tool_class.permitted?(agent: agent)).to be(false)
  end

  it "lets an account agent through when its CREATOR holds the permission (positive control)" do
    agent = create(:ai_agent, account: account, creator: holder) # holder: owner, holds every permission

    expect(tool_class.permitted?(agent: agent)).to be(true)
  end

  it "refuses an account agent when its creator does not hold the permission (the other arm)" do
    other = create(:account)
    creator = create(:user, account: other, permissions: []) # explicit []: no owner grant, so the creator holds nothing

    expect(tool_class.permitted?(agent: create(:ai_agent, account: other, creator: creator))).to be(false)
  end

  # IMP-82db8ba318aa review decision: User#has_permission? consults only
  # roles/role_permissions and does not itself check `active?` — without an
  # explicit `creator&.active?` guard, an offboarded creator would keep
  # conferring authority to every agent they made for as long as their roles
  # survive the deactivation.
  it "refuses when the creator holds the permission but is INACTIVE" do
    creator = create(:user, account: account, permissions: [ "ai.agents.manage" ], status: "inactive")
    agent = create(:ai_agent, account: account, creator: creator)

    expect(tool_class.permitted?(agent: agent)).to be(false)
  end

  # system.admin short-circuits through User#has_permission? itself
  # (user.rb) — this method does not special-case it, and this pins that
  # the pass-through still works after the rewrite.
  it "lets an active creator with system.admin through, regardless of the specific REQUIRED_PERMISSION" do
    creator = create(:user, account: account, permissions: [ "system.admin" ])
    agent = create(:ai_agent, account: account, creator: creator)

    expect(tool_class.permitted?(agent: agent)).to be(true)
  end

  # IMP-82db8ba318aa review round 2: `active?` alone is one clause short of
  # Authentication#authenticate_request's own standard
  # (`user&.active? && user.account&.active?`) — a personally-active creator
  # whose ACCOUNT is suspended must not keep conferring authority either.
  it "refuses when the creator is personally active but their ACCOUNT is suspended" do
    suspended_account = create(:account, :suspended)
    creator = create(:user, account: suspended_account, permissions: [ "ai.agents.manage" ])
    agent = create(:ai_agent, account: suspended_account, creator: creator)

    expect(tool_class.permitted?(agent: agent)).to be(false)
  end

  it "refuses when the creator is personally active but their ACCOUNT is cancelled" do
    cancelled_account = create(:account, :cancelled)
    creator = create(:user, account: cancelled_account, permissions: [ "ai.agents.manage" ])
    agent = create(:ai_agent, account: cancelled_account, creator: creator)

    expect(tool_class.permitted?(agent: agent)).to be(false)
  end

  # Defensive: the codebase already recognises cross-account-creator as a
  # hazard worth refusing (Ai::Agents::AccountPrincipalResolver#creator
  # explicitly refuses a user from a different account before using one as
  # a creator), but this gate did not check it. No production path reaches
  # this today (creator_id and account_id are set together everywhere a
  # real agent is minted), so this is a defensive assertion against a class
  # of bug, not a reproduction of a live one.
  it "refuses when the creator belongs to a DIFFERENT account than the agent" do
    other_account = create(:account)
    foreign_creator = create(:user, account: other_account, permissions: [ "ai.agents.manage" ])
    agent = create(:ai_agent, account: account, creator: foreign_creator)

    expect(tool_class.permitted?(agent: agent)).to be(false)
  end

  # Normalizes to a strict boolean (review round 2): every sibling rung in
  # #permitted? returns explicit false, and `creator&.active? && ...` alone
  # yields nil (not false) when creator itself is nil. Unreachable in real
  # use (creator is DB-guaranteed non-nil for this population), so this
  # stubs `agent.creator` directly to exercise the hypothetical — a future
  # `== false` or serialized `permitted` field would otherwise diverge on
  # nil if that guarantee were ever weakened.
  it "returns a strict boolean, not nil, even if creator could somehow be nil" do
    agent = create(:ai_agent, account: account, creator: holder)
    allow(agent).to receive(:creator).and_return(nil)

    expect(tool_class.permitted?(agent: agent)).to eq(false) # not merely falsy — eq, not be_falsey
  end
end
