# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skill, type: :model do
  describe "provenance / trust_level (G6)" do
    it "defaults to internal provenance and trusted trust_level" do
      skill = create(:ai_skill)

      expect(skill.provenance).to eq("internal")
      expect(skill.trust_level).to eq("trusted")
      expect(skill).to be_trusted
      expect(skill).to be_internal_provenance
    end

    it "validates provenance is one of the allowed values" do
      skill = build(:ai_skill, provenance: "totally-made-up")

      expect(skill).not_to be_valid
      expect(skill.errors[:provenance]).to be_present
    end

    it "validates trust_level is one of the allowed values" do
      skill = build(:ai_skill, trust_level: "kinda-trusted")

      expect(skill).not_to be_valid
      expect(skill.errors[:trust_level]).to be_present
    end

    it "accepts every declared provenance and trust_level value" do
      Ai::Skill::PROVENANCES.each do |prov|
        expect(build(:ai_skill, provenance: prov)).to be_valid
      end
      Ai::Skill::TRUST_LEVELS.each do |lvl|
        expect(build(:ai_skill, trust_level: lvl)).to be_valid
      end
    end

    it "exposes trust predicates" do
      expect(build(:ai_skill, trust_level: "review")).to be_needs_review
      expect(build(:ai_skill, trust_level: "untrusted")).to be_untrusted
      expect(build(:ai_skill, :community)).to be_external_provenance
    end

    it "scopes by trust level" do
      trusted   = create(:ai_skill, trust_level: "trusted")
      review    = create(:ai_skill, trust_level: "review")
      untrusted = create(:ai_skill, trust_level: "untrusted")

      expect(described_class.trusted).to include(trusted)
      expect(described_class.needs_review).to include(review)
      expect(described_class.untrusted).to include(untrusted)
      expect(described_class.untrusted).not_to include(trusted)
    end

    it "surfaces provenance + trust_level in skill_summary" do
      summary = create(:ai_skill, :community, trust_level: "review").skill_summary

      expect(summary[:provenance]).to eq("community")
      expect(summary[:trust_level]).to eq("review")
    end
  end
end
