# frozen_string_literal: true

require "rails_helper"

# The global-upsert seed helpers (find_or_initialize_global / find_or_create_global)
# were hoisted out of Ai::Agent into GloballyScopable so any global-scopable model
# can seed canonical GLOBAL (account_id nil) content keyed by a natural key.
# Exercised here on Ai::Skill (a representative includer with slug/source_key/
# is_system); Ai::Agent's own seed coverage lives in core_agents_global_seed_spec.
RSpec.describe GloballyScopable do
  describe ".find_or_create_global" do
    it "creates a GLOBAL record, running the block only on create" do
      skill = Ai::Skill.find_or_create_global(slug: "platform-skill") do |s|
        s.name = "Platform Skill"
        s.category = "productivity"
        s.status = "active"
      end

      expect(skill).to be_persisted
      expect(skill.account_id).to be_nil
      expect(skill.global?).to be(true)
      expect(skill.is_system).to be(true)
      expect(skill.source_key).to eq("platform-skill")
      expect(skill.name).to eq("Platform Skill")
    end

    it "is idempotent — a re-run finds the same row and does not re-run the block" do
      first = Ai::Skill.find_or_create_global(slug: "idem-skill") do |s|
        s.name = "Original"
        s.category = "productivity"
        s.status = "active"
      end

      block_ran = false
      second = Ai::Skill.find_or_create_global(slug: "idem-skill") do |s|
        block_ran = true
        s.name = "Should Not Apply"
      end

      expect(second.id).to eq(first.id)
      expect(block_ran).to be(false)
      expect(second.name).to eq("Original")
      expect(Ai::Skill.global.where(slug: "idem-skill").count).to eq(1)
    end

    it "converts a pre-existing ACCOUNT-scoped row to global in place (id stable)" do
      account = create(:account)
      legacy = create(:ai_skill, account: account, slug: "legacy-skill", is_system: false)

      converted = Ai::Skill.find_or_create_global(slug: "legacy-skill")

      expect(converted.id).to eq(legacy.id)
      expect(converted.reload.account_id).to be_nil
      expect(converted.is_system).to be(true)
    end

    it "defaults source_key to the natural-key value but honors an explicit one" do
      explicit = Ai::Skill.find_or_create_global(slug: "sk-explicit", source_key: "canonical-key") do |s|
        s.name = "Explicit"
        s.category = "productivity"
        s.status = "active"
      end
      expect(explicit.source_key).to eq("canonical-key")
    end

    it "raises when no natural key is given" do
      expect { Ai::Skill.find_or_create_global }.to raise_error(ArgumentError, /natural key/)
    end
  end

  describe ".find_or_initialize_global" do
    it "returns an unsaved global record the caller can finish and save" do
      skill = Ai::Skill.find_or_initialize_global(slug: "init-skill")
      expect(skill).to be_a_new(Ai::Skill)
      expect(skill.account_id).to be_nil
      expect(skill.is_system).to be(true)
      expect(skill.source_key).to eq("init-skill")
    end
  end
end
