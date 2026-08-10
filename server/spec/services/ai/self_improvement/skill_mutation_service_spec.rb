# frozen_string_literal: true

require "rails_helper"

# IMP-136447f24ceb — every query in this service referenced columns that do
# not exist (ai_skill_usage_records.success, SkillVersion#version_number/
# status, an AbTest shape with none of its real columns), so the weekly
# auto-evolution cron had never completed one query. These examples exercise
# the service directly — without the controller's per-account rescue that
# made the failure invisible — against the REAL schema.
RSpec.describe Ai::SelfImprovement::SkillMutationService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:skill) do
    create(:ai_skill, account: account, status: "active",
           category: "data", system_prompt: "Diagnose the fleet issue.")
  end

  def record_usages(target, outcome, count)
    count.times { target.record_usage!(outcome: outcome) }
  end

  describe "#auto_mutate_underperforming!" do
    it "mutates a skill whose success average is under the threshold" do
      record_usages(skill, "failure", 4)
      record_usages(skill, "success", 1)

      expect(service.auto_mutate_underperforming!(threshold: 0.4)).to eq(1)

      version = skill.versions.last
      expect(version).to be_present
      expect(version.is_ab_variant).to be(true)
      expect(version.system_prompt).to include("[MUTATION: failure_analysis]")
    end

    it "leaves healthy skills alone" do
      record_usages(skill, "success", 5)

      expect(service.auto_mutate_underperforming!(threshold: 0.4)).to eq(0)
      expect(skill.versions).to be_empty
    end
  end

  describe "#mutate! with failure_analysis" do
    it "creates a schema-valid A/B variant version and no Ai::AbTest row" do
      record_usages(skill, "failure", 3)

      expect {
        version = service.mutate!(skill: skill, strategy: "failure_analysis")

        expect(version).to be_a(Ai::SkillVersion)
        expect(version).to be_persisted
        expect(version.version).to eq("1")
        expect(version.change_type).to eq("ab_test")
        expect(version.ab_traffic_pct).to eq(20.0)
        expect(version.is_active).to be(false)
      }.not_to change(Ai::AbTest, :count)
    end

    it "keeps exactly one active A/B variant when mutating repeatedly" do
      # record_outcome!/end_ab_test resolve THE variant via .ab_variants.first —
      # a second mutation must retire the first variant's flag and traffic
      # slice (mirroring EvolutionService#start_ab_test) or later variants sit
      # inert forever while the oldest absorbs all A/B traffic.
      record_usages(skill, "failure", 3)
      service.mutate!(skill: skill, strategy: "failure_analysis")
      service.mutate!(skill: skill, strategy: "failure_analysis")

      variants = skill.versions.reload.where(is_ab_variant: true)
      expect(variants.count).to eq(1)
      expect(variants.first.version).to eq("2")
    end

    it "returns nil when the skill has no failures" do
      record_usages(skill, "success", 2)

      expect(service.mutate!(skill: skill, strategy: "failure_analysis")).to be_nil
    end
  end

  describe "#mutate! with peer_comparison" do
    it "builds the variant from better-performing peers in the same category" do
      peer = create(:ai_skill, account: account, status: "active",
                    category: "data", system_prompt: "Peer prompt.")
      record_usages(peer, "success", 5)
      record_usages(skill, "failure", 2)

      version = service.mutate!(skill: skill, strategy: "peer_comparison")

      expect(version).to be_persisted
      expect(version.system_prompt).to include("[MUTATION: peer_comparison]")
      expect(version.system_prompt).to include("Peer prompt.")
    end
  end
end
