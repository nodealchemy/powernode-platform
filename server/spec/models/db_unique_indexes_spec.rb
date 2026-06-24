# frozen_string_literal: true

require 'rails_helper'

# Proves the DB-LEVEL unique indexes added by
# db/migrate/20250101000012_add_unique_indexes_for_name_uniqueness.rb actually
# enforce uniqueness — not just the model `validates ... uniqueness` checks.
#
# Each example bypasses validations with `save(validate: false)` so the model
# guard cannot mask a missing/absent index: if the DB constraint is gone, the
# duplicate row inserts cleanly and the example fails. With the index in place
# the insert raises ActiveRecord::RecordNotUnique. This is the race-condition
# guard two concurrent validated requests would otherwise defeat.
RSpec.describe 'DB-level unique indexes (race guard)', type: :model do
  describe 'Ai::AgentTeam unique (account_id, name)' do
    it 'raises RecordNotUnique on a duplicate (account_id, name), bypassing validation' do
      existing = create(:ai_agent_team)
      dup = build(:ai_agent_team, name: existing.name, account: existing.account)

      expect { dup.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'permits the same name under a different account' do
      existing = create(:ai_agent_team)
      other = build(:ai_agent_team, name: existing.name, account: create(:account))

      expect { other.save(validate: false) }.not_to raise_error
    end
  end

  describe 'ValidationRule unique (name)' do
    it 'raises RecordNotUnique on a duplicate name, bypassing validation' do
      existing = create(:validation_rule)
      dup = build(:validation_rule, name: existing.name)

      expect { dup.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'Ai::AgentLineage unique (parent_agent_id, child_agent_id)' do
    it 'raises RecordNotUnique on a duplicate (parent, child) edge, bypassing validation' do
      existing = create(:ai_agent_lineage)
      dup = build(:ai_agent_lineage,
                  account: existing.account,
                  parent_agent: existing.parent_agent,
                  child_agent: existing.child_agent)

      expect { dup.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
