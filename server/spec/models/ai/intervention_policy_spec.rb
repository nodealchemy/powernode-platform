# frozen_string_literal: true

require "rails_helper"

# IMP-89c398dcbc15 — a policy row is identified by its FULL key:
# (account, scope, agent, user, action_category, priority, conditions).
# The five columns without priority and conditions are NOT an identity: a
# conditional tier (auto_approve at priority 20 under trust_tier_minimum
# "trusted" beside require_approval at priority 10 with no conditions) shares
# them on purpose, and that pair is the trust-tier safety mechanism.
RSpec.describe Ai::InterventionPolicy do
  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account) }

  def build_policy(**overrides)
    described_class.new({
      account: account, scope: "agent", ai_agent_id: agent.id, action_category: "release.promote",
      policy: "require_approval", priority: 10, conditions: {}, is_active: true
    }.merge(overrides))
  end

  describe "full-key uniqueness" do
    before { build_policy.save! }

    it "refuses a second row on the same full key, naming the existing row" do
      dup = build_policy(policy: "auto_approve")

      expect(dup).not_to be_valid
      expect(dup.errors[:base].join).to match(/already exists.*scope, agent, user, priority and conditions/i)
    end

    it "refuses the duplicate at the database too, not only in the model" do
      expect { build_policy(policy: "auto_approve").save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "treats an INACTIVE row as occupying the key" do
      described_class.where(account: account).update_all(is_active: false)

      expect(build_policy).not_to be_valid
    end

    it "collides two agent-less, user-less rows (NULLs are not distinct)" do
      build_policy(scope: "global", ai_agent_id: nil, action_category: "status_update", priority: 0).save!

      dup = build_policy(scope: "global", ai_agent_id: nil, action_category: "status_update", priority: 0)
      expect(dup).not_to be_valid
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "keeps the conditional trust-tier pair: same five columns, different priority and conditions" do
      tier = build_policy(policy: "auto_approve", priority: 20, conditions: { "trust_tier_minimum" => "trusted" })

      expect(tier).to be_valid
      expect { tier.save! }.not_to raise_error
    end

    it "allows the same priority when the conditions differ" do
      expect(build_policy(conditions: { "environments" => %w[staging] })).to be_valid
    end

    it "compares conditions as canonical jsonb, so key order does not make a row distinct" do
      build_policy(priority: 3, conditions: { "a" => 1, "b" => 2 }).save!

      expect(build_policy(priority: 3, conditions: { "b" => 2, "a" => 1 })).not_to be_valid
    end

    it "does not count the row itself when it is updated" do
      row = described_class.find_by!(account: account, action_category: "release.promote")

      expect(row.update(policy: "auto_approve")).to be(true)
    end

    it "does not collide across accounts" do
      other = create(:account)
      other_agent = create(:ai_agent, account: other)

      expect(build_policy(account: other, ai_agent_id: other_agent.id)).to be_valid
    end
  end

  describe "conditions normalisation" do
    it "stores {} for a nil conditions value, so it cannot dodge the unique index as NULL" do
      row = build_policy(conditions: nil)
      row.save!

      expect(row.reload.conditions).to eq({})
    end
  end

  describe "#precedence_key" do
    it "extends specificity_key with restrictiveness, then id, and leaves specificity_key untouched" do
      row = build_policy(policy: "require_approval").tap(&:save!)

      expect(row.specificity_key).to eq([ 0, 1, 1, 10 ])
      expect(row.precedence_key).to eq([ 0, 1, 1, 10, described_class::POLICIES.index("require_approval"), row.id.to_s ])
    end

    it "ranks every verb strictly, laxest first, ending at block" do
      keys = described_class::POLICIES.map { |verb| described_class.new(policy: verb, priority: 1).precedence_key[4] }

      expect(keys).to eq(keys.sort)
      expect(keys.uniq.size).to eq(described_class::POLICIES.size)
      expect(described_class::POLICIES.first).to eq("auto_approve")
      expect(described_class::POLICIES.last).to eq("block")
    end

    it "ranks an unknown verb as the most restrictive (fail safe)" do
      unknown = described_class.new(policy: "something_new", priority: 1)
      block   = described_class.new(policy: "block", priority: 1)

      expect(unknown.precedence_key[4]).to be > block.precedence_key[4]
    end
  end
end
