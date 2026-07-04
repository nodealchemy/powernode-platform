# frozen_string_literal: true

require "rails_helper"

# Pins the fix for the skill-seed globalization dupe bug: db/seeds/ai_skills_seed.rb
# used to upsert GLOBAL skills via find_or_initialize_by(source_key:, account_id: nil).
# A pre-globalization ACCOUNT-scoped row (source_key nil) never matches that finder,
# so re-seeding inserted a brand-new, empty global row instead of converting the
# account row in place — leaving two coexisting is_system rows per slug (see
# db/migrate/20260704000001_dedupe_skill_seed_globals.rb, which reconciles the
# duplicates this already produced). The fix upserts via
# Ai::Skill.find_or_initialize_global(slug:, source_key:), which converts the
# existing account row in place (id stable) instead of duplicating it.
RSpec.describe "db/seeds/ai_skills_seed.rb", type: :seed do
  def run_seed!
    seeds = Module.new do
      def self.baseline? = true
      def self.demo? = false
    end
    stub_const("Powernode::Seeds", seeds)
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    load Rails.root.join("db", "seeds", "ai_skills_seed.rb")
  end

  let!(:account) { create(:account) }

  describe "fresh seed" do
    before { run_seed! }

    it "creates the global productivity skill" do
      skill = Ai::Skill.global.find_by(slug: "productivity")
      expect(skill).to be_present
      expect(skill.source_key).to eq("productivity")
      expect(skill.is_system).to be(true)
    end

    it "is idempotent (no duplicates on re-run)" do
      expect { run_seed! }
        .not_to change { Ai::Skill.where(slug: "productivity", is_system: true).count }
    end
  end

  describe "idempotent in-place globalization of a pre-existing (pre-globalization) account row" do
    it "converts the existing account-scoped row in place instead of duplicating it" do
      legacy = create(:ai_skill, account: account, is_system: true, slug: "productivity",
                                  name: "Old Productivity Skill", category: "productivity",
                                  source_key: nil, cloned_from_id: nil)

      run_seed!
      legacy.reload

      expect(legacy.account_id).to be_nil # converted to global in place (id stable)
      expect(legacy.source_key).to eq("productivity")
      expect(legacy.name).to eq("Productivity Assistant")
      expect(Ai::Skill.where(slug: "productivity", is_system: true).count).to eq(1)
    end
  end

  describe "concierge skill" do
    it "converts an existing pre-globalization account row in place instead of duplicating it" do
      legacy = create(:ai_skill, account: account, is_system: true, slug: "powernode-concierge",
                                  name: "Old Concierge", category: "skill_management",
                                  source_key: nil, cloned_from_id: nil)

      run_seed!
      legacy.reload

      expect(legacy.account_id).to be_nil
      expect(legacy.source_key).to eq("powernode-concierge")
      expect(Ai::Skill.where(slug: "powernode-concierge", is_system: true).count).to eq(1)
    end
  end
end
