# frozen_string_literal: true

require "rails_helper"

# Increment D6 — the weekly skill auto-evolution cron is OFF unless an operator
# turns it on.
#
# `AiSkillAutoEvolutionJob` posts here every Monday, for EVERY active account,
# with no feature flag and no approval gate: the `dev.skill_refine` gate lives
# on the `auto_evolve_skill` MCP verb, not on this endpoint. It creates A/B
# prompt variants at 20% traffic that Ai::SkillGraph::EvolutionService serves.
# The audit's reading was that it is harmless only by accident, because what it
# writes is currently inert — and it stops being harmless the moment increment
# D5 makes an activated version's prompt reach a runtime reader.
#
# Both arms, because a gate that refuses everything and a gate that refuses
# nothing look identical from one example.
RSpec.describe "internal auto_evolve is gated on a SiteSetting", type: :request do
  let(:setting) { Ai::SelfImprovement::SkillMutationService::AUTO_EVOLUTION_SETTING }

  before { SiteSetting.where(key: setting).delete_all }
  after  { SiteSetting.where(key: setting).delete_all }

  describe "Ai::SelfImprovement::SkillMutationService.auto_evolution_enabled?" do
    it "is false when the row is absent, so a deployment that never seeded it is gated" do
      expect(SiteSetting.exists?(key: setting)).to be(false)
      expect(described_class_service.auto_evolution_enabled?).to be(false)
    end

    it "is false when the row says false" do
      SiteSetting.set(setting, "false", setting_type: "boolean")

      expect(described_class_service.auto_evolution_enabled?).to be(false)
    end

    it "is true only when the row says true" do
      SiteSetting.set(setting, "true", setting_type: "boolean")

      expect(described_class_service.auto_evolution_enabled?).to be(true)
    end

    # The string "false" is TRUTHY in Ruby, and it is reachable: a
    # `boolean`-typed row casts on read, but a row stored under any other type
    # comes back as the raw string. A gate using the value for truthiness would
    # read a seeded OFF row as ON — the direction that matters — so the
    # predicate casts rather than tests.
    it "does not read the string \"false\" as enabled" do
      SiteSetting.set(setting, "false", setting_type: "string")

      expect(SiteSetting.get(setting)).to eq("false")
      expect(described_class_service.auto_evolution_enabled?).to be(false)
    end
  end

  # The endpoint is mTLS-internal, so the gate is asserted on the controller
  # action directly rather than over HTTP: the oracle is "the mutation service
  # is never constructed", which is what actually protects the skills.
  describe "the endpoint's no-op arm" do
    let(:controller) { Api::V1::Internal::Ai::SkillsController.new }

    it "never constructs the mutation service when the setting is off" do
      expect(described_class_service).not_to receive(:new)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      expect(controller).to receive(:render_success) do |payload|
        expect(payload[:enabled]).to be(false)
        expect(payload[:mutated]).to eq(0)
        expect(payload[:reason]).to include(setting)
      end

      controller.auto_evolve
    end

    it "logs the reason rather than failing silently" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      allow(controller).to receive(:render_success)
      expect(Rails.logger).to receive(:info).with(/Skipped:.*#{Regexp.escape(setting)}/)

      controller.auto_evolve
    end

    # THE OTHER ARM. With the setting on, the sweep runs — so the example above
    # cannot be passing because the action is broken.
    it "runs the sweep when the setting is on" do
      SiteSetting.set(setting, "true", setting_type: "boolean")
      create(:account)
      service = instance_double(Ai::SelfImprovement::SkillMutationService)
      allow(described_class_service).to receive(:new).and_return(service)
      allow(service).to receive(:auto_mutate_underperforming!).and_return(2)

      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      expect(controller).to receive(:render_success) do |payload|
        expect(payload[:enabled]).to be(true)
        expect(payload[:mutated]).to be >= 2
      end

      controller.auto_evolve
    end
  end

  # The MCP verb keeps its OWN gate and must not be disarmed by this one: the
  # setting is read at the endpoint, never inside the shared service, precisely
  # so an operator who leaves the cron off can still evolve a skill by hand
  # through the approval-gated verb.
  describe "the MCP verb is unaffected" do
    it "declares its approval gate independently of the setting" do
      declaration = Ai::Tools::SelfImprovementTool.declared_action("auto_evolve_skill")

      expect(declaration[:action_category]).to eq("dev.skill_refine")
      expect(declaration[:mutating]).to be(true)
    end

    it "does not consult the setting inside the shared service entry point" do
      source = File.read(
        Rails.root.join("app/services/ai/self_improvement/skill_mutation_service.rb")
      )
      body = source[/def auto_mutate_underperforming!.*?\n      end/m]

      expect(body).not_to be_nil
      expect(body).not_to include("auto_evolution_enabled?"),
        "the gate moved into the shared service, which silently disarms the approval-gated MCP verb too"
    end
  end

  def described_class_service
    Ai::SelfImprovement::SkillMutationService
  end
end
