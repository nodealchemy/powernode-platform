# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260930130000_dedupe_ai_intervention_policies.rb")

# IMP-89c398dcbc15. A duplicate is a row on the FULL key (account, scope, agent,
# user, category, priority, conditions), never the five columns without priority
# and conditions: those are shared on purpose by conditional trust tiers.
RSpec.describe DedupeAiInterventionPolicies do
  # The migration removes rows the unique index now forbids, so the spec has to
  # drop the index to be able to build them. DDL is transactional in Postgres
  # and the example rolls back, restoring it.
  before do
    ActiveRecord::Base.connection.remove_index(:ai_intervention_policies, name: "idx_ai_intervention_policies_full_key")
    allow(migration).to receive(:say)
  end

  after(:context) { ActiveRecord::Base.connection.clear_cache! }

  subject(:migration) { described_class.new }

  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account) }
  let(:t0)      { Time.utc(2026, 9, 5, 12, 0, 0) }

  def policy_row(policy:, updated_at: t0, priority: 10, conditions: {}, agent_id: agent.id, category: "release.promote",
                 scope: "agent", acct: account)
    row = Ai::InterventionPolicy.new(
      account: acct, scope: scope, ai_agent_id: agent_id, action_category: category, policy: policy,
      priority: priority, conditions: conditions, is_active: true, created_at: updated_at, updated_at: updated_at
    )
    row.save!(validate: false)
    row
  end

  def remaining_ids = Ai::InterventionPolicy.pluck(:id)

  it "keeps the most recently updated row of a duplicate set and removes the older one" do
    old = policy_row(policy: "require_approval", updated_at: t0)
    new = policy_row(policy: "auto_approve", updated_at: t0 + 22.days)

    migration.up

    expect(remaining_ids).to eq([ new.id ])
    expect(Ai::InterventionPolicy.where(id: old.id)).not_to exist
  end

  it "keeps the greatest id when updated_at ties" do
    rows = Array.new(3) { policy_row(policy: "require_approval") }

    migration.up

    expect(remaining_ids).to eq([ rows.map(&:id).max ])
  end

  it "keeps a conditional tier intact: auto_approve@20 under trust_tier_minimum beside require_approval@10" do
    tier = policy_row(policy: "auto_approve", priority: 20, conditions: { "trust_tier_minimum" => "trusted" },
                      category: "dev.prompt_refine")
    base = policy_row(policy: "require_approval", priority: 10, category: "dev.prompt_refine")

    migration.up

    expect(remaining_ids).to contain_exactly(tier.id, base.id)
  end

  it "keeps rows that differ only by conditions, or only by priority" do
    a = policy_row(policy: "auto_approve", conditions: { "environments" => %w[staging] })
    b = policy_row(policy: "auto_approve", conditions: {})
    c = policy_row(policy: "auto_approve", priority: 11)

    migration.up

    expect(remaining_ids).to contain_exactly(a.id, b.id, c.id)
  end

  it "compares conditions as canonical jsonb (key order is not a difference)" do
    policy_row(policy: "require_approval", conditions: { "a" => 1, "b" => 2 }, updated_at: t0)
    new = policy_row(policy: "require_approval", conditions: { "b" => 2, "a" => 1 }, updated_at: t0 + 1.day)

    migration.up

    expect(remaining_ids).to eq([ new.id ])
  end

  it "dedups agent-less rows (NULL agent and user are equal within a set)" do
    policy_row(policy: "notify_and_proceed", agent_id: nil, scope: "global", category: "status_update", priority: 0)
    new = policy_row(policy: "notify_and_proceed", agent_id: nil, scope: "global", category: "status_update",
                     priority: 0, updated_at: t0 + 1.day)

    migration.up

    expect(remaining_ids).to eq([ new.id ])
  end

  it "does not merge rows across accounts or across agents" do
    other = create(:account)
    other_agent = create(:ai_agent, account: account)
    rows = [
      policy_row(policy: "require_approval"),
      policy_row(policy: "require_approval", acct: other),
      policy_row(policy: "require_approval", agent_id: other_agent.id)
    ]

    migration.up

    expect(remaining_ids).to match_array(rows.map(&:id))
  end

  it "treats an inactive copy as a duplicate" do
    old = policy_row(policy: "require_approval", updated_at: t0)
    old.update_columns(is_active: false)
    new = policy_row(policy: "require_approval", updated_at: t0 + 1.day)

    migration.up

    expect(remaining_ids).to eq([ new.id ])
  end

  it "resolves the observed release.promote conflict to the operator's newer auto_approve" do
    policy_row(policy: "require_approval", updated_at: Time.utc(2026, 9, 5))
    edited = policy_row(policy: "auto_approve", updated_at: Time.utc(2026, 9, 27))

    migration.up

    expect(Ai::InterventionPolicy.sole.id).to eq(edited.id)
    expect(Ai::InterventionPolicy.sole.policy).to eq("auto_approve")
  end

  it "reports every removed row, flags a verb conflict, and says nothing was removed when there is nothing to do" do
    old = policy_row(policy: "require_approval", updated_at: t0)
    new = policy_row(policy: "auto_approve", updated_at: t0 + 1.day)
    lines = []
    allow(migration).to receive(:say) { |line| lines << line }

    migration.up

    removal = lines.find { |l| l.include?("removed #{old.id}") }
    expect(removal).to include("release.promote", "policy=require_approval", "priority=10", "updated_at=",
                               "kept #{new.id}", "CONFLICT, kept auto_approve")

    lines.clear
    migration.up
    expect(lines).to eq([ "IMP-89c398dcbc15: 0 surplus intervention policy row(s) to remove" ])
  end

  it "marks a same-verb removal as such" do
    policy_row(policy: "require_approval", updated_at: t0)
    policy_row(policy: "require_approval", updated_at: t0 + 1.day)
    lines = []
    allow(migration).to receive(:say) { |line| lines << line }

    migration.up

    expect(lines.join("\n")).to include("same verb")
    expect(lines.join("\n")).not_to include("CONFLICT")
  end

  it "NEVER raises: a failing delete logs, leaves every row, and the migration returns" do
    rows = [ policy_row(policy: "require_approval", updated_at: t0), policy_row(policy: "auto_approve", updated_at: t0 + 1.day) ]
    allow(migration).to receive(:delete_rows).and_raise(ActiveRecord::StatementInvalid, "boom")
    lines = []
    allow(migration).to receive(:say) { |line| lines << line }
    allow(Rails.logger).to receive(:error)

    expect { migration.up }.not_to raise_error

    expect(remaining_ids).to match_array(rows.map(&:id))
    expect(lines.join("\n")).to include("dedup FAILED", "no rows were removed", "boom")
    expect(Rails.logger).to have_received(:error).with(/dedup FAILED/)
  end

  it "NEVER raises when the read itself fails" do
    allow(migration).to receive(:surplus_rows).and_raise(PG::UndefinedTable, "no such table")

    expect { migration.up }.not_to raise_error
  end

  it "has a no-op down" do
    expect { migration.down }.not_to raise_error
  end
end
