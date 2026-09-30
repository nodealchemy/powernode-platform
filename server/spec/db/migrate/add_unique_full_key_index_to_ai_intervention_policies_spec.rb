# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260930130100_add_unique_full_key_index_to_ai_intervention_policies.rb")

# IMP-89c398dcbc15. The index migration must never raise (a raising data
# migration crash-loops Rails at boot, 09-28): with duplicates left over from a
# failed dedup it SKIPS with a warning, and on a schema-loaded database that
# already carries the index it does nothing.
RSpec.describe AddUniqueFullKeyIndexToAiInterventionPolicies do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:index_name) { described_class::INDEX }
  let(:account)    { create(:account) }
  let(:agent)      { create(:ai_agent, account: account) }
  let(:lines)      { [] }

  before do
    allow(migration).to receive(:say) { |line| lines << line }
    allow(Rails.logger).to receive(:warn)
  end

  # DDL is transactional in Postgres; the example rolls all of this back.
  after(:context) { ActiveRecord::Base.connection.clear_cache! }

  def drop_index! = connection.remove_index(:ai_intervention_policies, name: index_name)
  def index_present? = connection.index_name_exists?(:ai_intervention_policies, index_name)

  def policy_row(policy: "require_approval", updated_at: Time.current, **overrides)
    row = Ai::InterventionPolicy.new({
      account: account, scope: "agent", ai_agent_id: agent.id, action_category: "release.promote",
      policy: policy, priority: 10, conditions: {}, is_active: true, created_at: updated_at, updated_at: updated_at
    }.merge(overrides))
    row.save!(validate: false)
    row
  end

  it "does nothing on a database that already carries the index (a fresh schema:load then migrate)" do
    expect(index_present?).to be(true)

    expect { migration.up }.not_to raise_error

    expect(lines.join("\n")).to include("already exists, skipping")
  end

  context "when the index is missing" do
    before { drop_index! }

    it "creates a UNIQUE, NULLS NOT DISTINCT index on the full key" do
      migration.up

      index = connection.indexes(:ai_intervention_policies).find { |i| i.name == index_name }
      expect(index).to be_present
      expect(index.unique).to be(true)
      expect(index.columns).to eq(%w[account_id scope ai_agent_id user_id action_category priority conditions])
      expect(index.nulls_not_distinct).to be(true)
    end

    it "then refuses a duplicate, including two agent-less rows" do
      migration.up
      policy_row(scope: "global", ai_agent_id: nil, action_category: "status_update", priority: 0)

      expect { policy_row(scope: "global", ai_agent_id: nil, action_category: "status_update", priority: 0) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "still allows the conditional trust-tier pair" do
      migration.up
      policy_row(policy: "auto_approve", priority: 20, conditions: { "trust_tier_minimum" => "trusted" })

      expect { policy_row(priority: 10) }.not_to raise_error
    end

    it "SKIPS with a warning, and does not raise, while duplicates remain" do
      policy_row(policy: "require_approval")
      policy_row(policy: "auto_approve")

      expect { migration.up }.not_to raise_error

      expect(index_present?).to be(false)
      expect(lines.join("\n")).to include("NOT created", "1 duplicate set(s) remain")
      expect(Rails.logger).to have_received(:warn).with(/NOT created/)
    end

    it "counts a NULL-agent duplicate set as remaining" do
      2.times { policy_row(scope: "global", ai_agent_id: nil, action_category: "status_update", priority: 0) }

      migration.up

      expect(index_present?).to be(false)
    end

    it "builds the index on the retry once the duplicates are gone" do
      keep = policy_row(policy: "auto_approve")
      gone = policy_row(policy: "require_approval")
      migration.up
      expect(index_present?).to be(false)

      Ai::InterventionPolicy.where(id: gone.id).delete_all
      migration.up

      expect(index_present?).to be(true)
      expect(Ai::InterventionPolicy.pluck(:id)).to eq([ keep.id ])
    end

    it "NEVER raises when the index cannot be created" do
      allow(migration).to receive(:add_index).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { migration.up }.not_to raise_error

      expect(lines.join("\n")).to include("NOT created", "boom")
    end

    it "backfills NULL and JSON-null conditions to {} and makes the column NOT NULL, so they cannot dodge the index" do
      connection.change_column_null(:ai_intervention_policies, :conditions, true)
      null_row = policy_row(priority: 1)
      json_null_row = policy_row(priority: 2)
      connection.execute("UPDATE ai_intervention_policies SET conditions = NULL WHERE id = #{connection.quote(null_row.id)}")
      connection.execute("UPDATE ai_intervention_policies SET conditions = 'null'::jsonb WHERE id = #{connection.quote(json_null_row.id)}")

      migration.up

      expect(Ai::InterventionPolicy.where(id: [ null_row.id, json_null_row.id ]).pluck(:conditions)).to eq([ {}, {} ])
      expect(connection.columns(:ai_intervention_policies).find { |c| c.name == "conditions" }.null).to be(false)
      expect(index_present?).to be(true)
    end

    it "treats NULL conditions and {} as the same row when it counts duplicates" do
      connection.change_column_null(:ai_intervention_policies, :conditions, true)
      policy_row(conditions: {})
      dup = policy_row(conditions: {})
      connection.execute("UPDATE ai_intervention_policies SET conditions = NULL WHERE id = #{connection.quote(dup.id)}")

      migration.up

      expect(index_present?).to be(false)
      expect(lines.join("\n")).to include("1 duplicate set(s) remain")
    end
  end

  describe "#down" do
    it "removes the index and relaxes the column" do
      migration.down

      expect(index_present?).to be(false)
      expect(connection.columns(:ai_intervention_policies).find { |c| c.name == "conditions" }.null).to be(true)
    end

    it "is safe to run when the index is already gone" do
      drop_index!

      expect { migration.down }.not_to raise_error
    end
  end
end
