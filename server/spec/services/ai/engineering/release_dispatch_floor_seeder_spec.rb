# frozen_string_literal: true

require "rails_helper"

# HIER-P2B-ENG — the `release.build_dispatch` floor, and the reason it is a
# SEAM rather than a line in the seed.
#
# `system_dispatch_module_build_batch` is gate-routed on release.build_dispatch.
# The code ships with the deploy; `db:seed` runs on FIRST BOOT ONLY, so on an
# install that is already up the row would be absent and the category would
# resolve through Ai::InterventionPolicyService's require_approval default —
# every build dispatch parked. `rake db:seed:engineering_release_floor` calls
# this class, which is why it must be idempotent, per-account, and incapable of
# clobbering an operator's own row.
RSpec.describe Ai::Engineering::ReleaseDispatchFloorSeeder do
  let!(:account) { create(:account) }

  def floor_rows(acct = account)
    Ai::InterventionPolicy.where(account: acct, action_category: described_class::CATEGORY,
                                 scope: "global", ai_agent_id: nil, user_id: nil)
  end

  describe ".ensure_for!" do
    it "writes the auto_approve floor when the account has none" do
      expect(described_class.ensure_for!(account)).to be(true)

      row = floor_rows.sole
      expect(row.policy).to eq("auto_approve")
      expect(row.priority).to eq(0)
      expect(row.is_active).to be(true)
      expect(row.conditions).to eq({})
    end

    it "is idempotent — a second call writes nothing and leaves one row" do
      described_class.ensure_for!(account)

      expect(described_class.ensure_for!(account)).to be(false)
      expect(floor_rows.count).to eq(1)
    end

    it "NEVER rewrites a row an operator retuned (absence-only)" do
      described_class.ensure_for!(account)
      floor_rows.sole.update!(policy: "require_approval", is_active: false)

      expect(described_class.ensure_for!(account)).to be(false)
      row = floor_rows.sole
      expect(row.policy).to eq("require_approval")
      expect(row.is_active).to be(false)
    end

    it "does not adopt an AGENT-scoped row for the same category as the floor" do
      agent = create(:ai_agent, account: account)
      Ai::InterventionPolicy.create!(account: account, action_category: described_class::CATEGORY,
                                     scope: "agent", ai_agent_id: agent.id, policy: "auto_approve",
                                     priority: 10, is_active: true)

      expect(described_class.ensure_for!(account)).to be(true)
      expect(floor_rows.count).to eq(1)
    end
  end

  describe ".ensure_all!" do
    it "covers EVERY account, which is what an established install needs" do
      other = create(:account)

      expect(described_class.ensure_all!).to eq(2)
      expect(floor_rows(account).count).to eq(1)
      expect(floor_rows(other).count).to eq(1)
      expect(described_class.ensure_all!).to eq(0)
    end
  end

  describe "the gate it exists for" do
    it "turns an agent-less caller's verdict from the require_approval default into auto_approve" do
      resolver = Ai::InterventionPolicyService.new(account: account)
      expect(resolver.resolve(action_category: described_class::CATEGORY)[:policy]).to eq("require_approval")

      described_class.ensure_for!(account)

      expect(Ai::InterventionPolicyService.new(account: account)
               .resolve(action_category: described_class::CATEGORY)[:policy]).to eq("auto_approve")
    end

    it "leaves the other release verbs at the require_approval default — they have no floor" do
      described_class.ensure_for!(account)
      resolver = Ai::InterventionPolicyService.new(account: account)

      %w[release.promote release.rollback release.deploy_platform].each do |category|
        expect(resolver.resolve(action_category: category)[:policy]).to eq("require_approval"),
                                                                        "#{category} should have no floor"
      end
    end
  end
end
