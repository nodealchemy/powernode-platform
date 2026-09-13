# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260913123000_make_blank_delegatable_actions_explicit.rb")

# IMP-d2873a16567e. Ai::DelegationPolicy#allows_action? now reads a blank
# delegatable_actions as NONE. Every row written before that meant "any action"
# by the same bytes, so the migration rewrites those rows to the explicit list
# of what they permitted — the action type delegation is checked as — rather
# than letting the new reading silently revoke them.
RSpec.describe MakeBlankDelegatableActionsExplicit do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }

  before { allow(migration).to receive(:say) }

  it "writes the explicit action list onto a row that still carries the blank list" do
    blank = create(:ai_delegation_policy, account: account, delegatable_actions: [])

    migration.up

    expect(blank.reload.delegatable_actions).to eq(%w[execute])
    expect(blank.allows_action?(Ai::TeamStrategies::HierarchicalStrategy::DELEGATED_ACTION_TYPE)).to be(true)
  end

  it "leaves a row that already names its actions exactly as it was" do
    listed = create(:ai_delegation_policy, account: account, delegatable_actions: %w[execute deploy])
    sentinel = create(:ai_delegation_policy, account: account, delegatable_actions: %w[none])

    migration.up

    expect(listed.reload.delegatable_actions).to eq(%w[execute deploy])
    expect(sentinel.reload.delegatable_actions).to eq(%w[none])
  end

  it "repairs a canonical (account-less) row too" do
    global = create(:ai_delegation_policy, account: nil, delegatable_actions: [])

    migration.up

    expect(global.reload.delegatable_actions).to eq(%w[execute])
  end

  it "refuses to run down: a repaired row cannot be told apart from one written explicitly" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
