# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Missions::ComposerRouter do
  let(:account) { double("account") }
  let(:mission) { double("mission", id: "mission-1", configuration: {}) }

  subject(:router) { described_class.new(account: account, mission: mission) }

  describe "#deterministic_provisioning?" do
    it "is true when use_case maps to a known role module" do
      known = ::Ai::Provisioning::PlanComposerService::ROLE_MODULE_FOR_USE_CASE.keys.first
      skip "no role-module use_cases defined" if known.nil?

      expect(router.deterministic_provisioning?("use_case" => known.to_s)).to be(true)
    end

    it "is true for a non-empty regions list" do
      expect(router.deterministic_provisioning?("regions" => ["us-east-1"])).to be(true)
    end

    it "ignores blank entries in regions" do
      expect(router.deterministic_provisioning?("regions" => ["", "  "])).to be(false)
    end

    it "is true when a preferred_provider is set" do
      expect(router.deterministic_provisioning?("preferred_provider" => "aws")).to be(true)
    end

    it "is true for a runtime_hint that maps to a real module" do
      hint = ::Ai::Provisioning::PlanComposerService::RUNTIME_HINT_TO_MODULE
               .find { |_, mod| mod.present? }&.first
      skip "no mappable runtime hints defined" if hint.nil?

      expect(router.deterministic_provisioning?("runtime_hint" => hint.to_s)).to be(true)
    end

    it "is false for a runtime_hint that maps to nil (e.g. none)" do
      expect(router.deterministic_provisioning?("runtime_hint" => "none")).to be(false)
    end

    it "is true for a positive scale.initial" do
      expect(router.deterministic_provisioning?("scale" => { "initial" => 2 })).to be(true)
    end

    it "is false for scale.initial == 0" do
      expect(router.deterministic_provisioning?("scale" => { "initial" => 0 })).to be(false)
    end

    it "is false for a novel intent with no provisioning signals" do
      expect(
        router.deterministic_provisioning?("intent" => "expose the metrics service over HTTPS")
      ).to be(false)
    end

    it "is false for a non-hash brief" do
      expect(router.deterministic_provisioning?(nil)).to be(false)
    end
  end

  describe "#select" do
    it "returns PlanComposerService for a recognized provisioning scenario" do
      expect(::Ai::Provisioning::PlanComposerService).to receive(:new)
        .with(account: account, mission: mission).and_return(:plan_composer)

      expect(router.select(brief: { "regions" => ["us-east-1"] })).to eq(:plan_composer)
    end

    it "returns MissionComposer (carrying the intent) for a novel intent" do
      expect(::Ai::Missions::MissionComposer).to receive(:new)
        .with(account: account, mission: mission, intent: "do something novel")
        .and_return(:mission_composer)

      expect(router.select(brief: { "intent" => "do something novel" })).to eq(:mission_composer)
    end

    it "defaults to the mission's stored brief when none is passed" do
      allow(mission).to receive(:configuration).and_return("brief" => { "regions" => ["us-east-1"] })
      expect(::Ai::Provisioning::PlanComposerService).to receive(:new).and_return(:plan_composer)

      expect(router.select).to eq(:plan_composer)
    end

    it "never instantiates both composers (no try-then-discard)" do
      expect(::Ai::Provisioning::PlanComposerService).not_to receive(:new)
      expect(::Ai::Missions::MissionComposer).to receive(:new).and_return(:mission_composer)

      router.select(brief: { "intent" => "novel" })
    end
  end

  describe ".extract_brief" do
    it "returns the brief hash from configuration" do
      m = double("mission", configuration: { "brief" => { "intent" => "x" } })
      expect(described_class.extract_brief(m)).to eq("intent" => "x")
    end

    it "returns {} when there is no brief or no configuration" do
      expect(described_class.extract_brief(double("mission", configuration: {}))).to eq({})
      expect(described_class.extract_brief(nil)).to eq({})
    end
  end
end
