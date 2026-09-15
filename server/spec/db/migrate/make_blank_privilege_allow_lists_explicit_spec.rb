# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260915010000_make_blank_privilege_allow_lists_explicit.rb")

# IMP-636a10c80024. Ai::AgentPrivilegePolicy now reads a blank allow-list as
# DENY. Every row written before that meant "unrestricted, bounded by the
# deny-list" by the same bytes, so the migration rewrites those lists to the
# explicit wildcard rather than letting the new reading revoke them.
RSpec.describe MakeBlankPrivilegeAllowListsExplicit do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }

  before { allow(migration).to receive(:say) }

  it "writes the wildcard onto every blank allow-list and keeps the deny-list bounding it" do
    blank = create(:ai_agent_privilege_policy, account: account, allowed_actions: [], allowed_tools: [],
                                               allowed_resources: [], denied_tools: %w[execute_code])

    migration.up

    blank.reload
    expect([ blank.allowed_actions, blank.allowed_tools, blank.allowed_resources ]).to all(eq(%w[*]))
    expect(blank.tool_allowed?("search")).to be(true)
    expect(blank.tool_allowed?("execute_code")).to be(false)
  end

  it "repairs the other values the old reading counted as empty ({} and \"\")" do
    odd = create(:ai_agent_privilege_policy, account: account)
    odd.update_columns(allowed_actions: {}, allowed_tools: "")

    migration.up

    odd.reload
    expect([ odd.allowed_actions, odd.allowed_tools ]).to all(eq(%w[*]))
  end

  # The old model raised on NULL and enforcement failed closed, so a NULL
  # allow-list already denied. Rewriting it to ["*"] would open the row up.
  it "leaves a null allow-list alone, so it keeps denying" do
    null = create(:ai_agent_privilege_policy, account: account)
    null.update_columns(allowed_actions: nil, allowed_tools: nil, allowed_resources: nil)

    migration.up

    null.reload
    expect([ null.allowed_actions, null.allowed_tools, null.allowed_resources ]).to all(be_nil)
    expect(null.tool_allowed?("search")).to be(false)
  end

  it "leaves a row that already names its allow-lists exactly as it was" do
    listed = create(:ai_agent_privilege_policy, account: account, allowed_actions: %w[read_data],
                                                allowed_tools: %w[search], allowed_resources: %w[documents])

    migration.up

    listed.reload
    expect(listed.allowed_actions).to eq(%w[read_data])
    expect(listed.allowed_tools).to eq(%w[search])
    expect(listed.allowed_resources).to eq(%w[documents])
  end

  it "refuses to run down: a repaired row cannot be told apart from one written explicitly" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
