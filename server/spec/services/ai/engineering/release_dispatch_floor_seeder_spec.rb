# frozen_string_literal: true

require "rails_helper"

# HIER-P2B-ENG — the account-wide engineering FLOORS, and the reason they are
# a SEAM rather than a line in the seed.
#
# `system_dispatch_module_build_batch` is gate-routed on release.build_dispatch;
# mutate_skill and auto_evolve_skill on dev.prompt_refine and dev.skill_refine
# (IMP-a51963f8717f, proposal §5 ruling 11c). The principals that legitimately
# call those verbs over MCP — an operator's mcp_client session, a dev-cell
# instance principal — own no agent-scoped row, so without a floor each
# category resolves through Ai::InterventionPolicyService's require_approval
# default and the call parks. The code ships with the deploy; `db:seed` runs on
# FIRST BOOT ONLY, so on an install that is already up the rows would be absent
# unless something re-runnable writes them: `rake db:seed:engineering_floors`
# (alias `engineering_release_floor`) and every boot-time governance reconcile
# call this class, which is why it must be idempotent, per-account, per-category
# and incapable of clobbering an operator's own row.
RSpec.describe Ai::Engineering::ReleaseDispatchFloorSeeder do
  let!(:account) { create(:account) }

  def floor_rows(acct = account, category = "release.build_dispatch")
    Ai::InterventionPolicy.where(account: acct, action_category: category,
                                 scope: "global", ai_agent_id: nil, user_id: nil)
  end

  def all_floor_rows(acct = account)
    Ai::InterventionPolicy.where(account: acct, action_category: described_class::CATEGORIES,
                                 scope: "global", ai_agent_id: nil, user_id: nil)
  end

  it "floors exactly the three categories the operator ruled on — build dispatch and the two refine verbs" do
    expect(described_class::CATEGORIES).to contain_exactly("release.build_dispatch", "dev.prompt_refine", "dev.skill_refine")
    described_class::CATEGORIES.each do |category|
      expect(Ai::InterventionPolicy.category_registered?(category)).to be(true), "#{category} is not a registered category"
    end
  end

  describe ".ensure_for!" do
    it "writes one auto_approve floor per category when the account has none, and reports the count" do
      expect(described_class.ensure_for!(account)).to eq(3)

      described_class::CATEGORIES.each do |category|
        row = floor_rows(account, category).sole
        expect(row.policy).to eq("auto_approve"), category
        expect(row.priority).to eq(0)
        expect(row.is_active).to be(true)
        expect(row.conditions).to eq({})
      end
    end

    it "is idempotent — a second call writes nothing and leaves one row per category" do
      described_class.ensure_for!(account)

      expect(described_class.ensure_for!(account)).to eq(0)
      expect(all_floor_rows.count).to eq(3)
    end

    it "fills only the category that is MISSING on an install that has the older single floor" do
      described_class.ensure_for!(account)
      floor_rows(account, "dev.skill_refine").sole.destroy!

      expect(described_class.ensure_for!(account)).to eq(1)
      expect(all_floor_rows.count).to eq(3)
    end

    it "NEVER rewrites a row an operator retuned (absence-only)" do
      described_class.ensure_for!(account)
      floor_rows(account, "dev.prompt_refine").sole.update!(policy: "require_approval", is_active: false)

      expect(described_class.ensure_for!(account)).to eq(0)
      row = floor_rows(account, "dev.prompt_refine").sole
      expect(row.policy).to eq("require_approval")
      expect(row.is_active).to be(false)
      expect(floor_rows(account, "release.build_dispatch").sole.policy).to eq("auto_approve")
    end

    it "does not adopt an AGENT-scoped row for the same category as the floor" do
      agent = create(:ai_agent, account: account)
      Ai::InterventionPolicy.create!(account: account, action_category: "dev.prompt_refine",
                                     scope: "agent", ai_agent_id: agent.id, policy: "auto_approve",
                                     priority: 10, is_active: true)

      expect(described_class.ensure_for!(account)).to eq(3)
      expect(floor_rows(account, "dev.prompt_refine").count).to eq(1)
    end
  end

  describe ".ensure_all!" do
    it "covers EVERY account, which is what an established install needs" do
      other = create(:account)

      expect(described_class.ensure_all!).to eq(6)
      expect(all_floor_rows(account).count).to eq(3)
      expect(all_floor_rows(other).count).to eq(3)
      expect(described_class.ensure_all!).to eq(0)
    end
  end

  describe "the gates it exists for" do
    it "turns an agent-less caller's verdict from the require_approval default into auto_approve for each floored category" do
      resolver = Ai::InterventionPolicyService.new(account: account)
      described_class::CATEGORIES.each do |category|
        expect(resolver.resolve(action_category: category)[:policy]).to eq("require_approval"), category
      end

      described_class.ensure_for!(account)

      after = Ai::InterventionPolicyService.new(account: account)
      described_class::CATEGORIES.each do |category|
        expect(after.resolve(action_category: category)[:policy]).to eq("auto_approve"), category
      end
    end

    it "is OUTRANKED by an agent's own row, so a seeded agent's verdict is unchanged" do
      agent = create(:ai_agent, account: account)
      Ai::InterventionPolicy.create!(account: account, action_category: "dev.skill_refine",
                                     scope: "agent", ai_agent_id: agent.id, policy: "require_approval",
                                     priority: 10, is_active: true)
      described_class.ensure_for!(account)

      resolver = Ai::InterventionPolicyService.new(account: account)
      expect(resolver.resolve(action_category: "dev.skill_refine", agent: agent)[:policy]).to eq("require_approval")
      expect(resolver.resolve(action_category: "dev.skill_refine")[:policy]).to eq("auto_approve")
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
