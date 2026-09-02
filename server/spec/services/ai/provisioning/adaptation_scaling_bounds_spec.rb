# frozen_string_literal: true

require "rails_helper"

# APO increment 3a (scale arm) — IMP-a343c2bf2fc9.
#
# Before this increment "bounds" had no per-project home. `InstancePool` carries
# min_size/max_size; a mission carried only a bare `watch_policies
# .auto_scale_max_replicas` ceiling read directly by the composer, with NO floor
# at all — the actuating skill clamped every scale-in at a hardcoded
# platform-wide `MIN_REPLICAS = 1`, so a project that must never drop below
# three replicas had no way to say so.
#
# Operator ruling 2026-09-02: scale-OUT may auto-apply within the project's
# DECLARED bounds; scale-IN and any removal take an approval regardless of
# policy. Defaults are SiteSetting-resolved, never hardcoded.
RSpec.describe "Adaptation per-project scaling bounds", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:watch_policies) { {} }

  let(:mission) do
    m = create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [ { "key" => "adapting", "label" => "Adapting", "order" => 0 } ],
      configuration: {
        "brief" => { "scale" => { "initial" => 3 } },
        "watch_policies" => watch_policies
      }
    )
    m.update_columns(status: "active")
    m.reload
  end

  # ------------------------------------------------------------------
  # 1. The per-project home: Ai::Mission#scaling_bounds
  # ------------------------------------------------------------------
  describe "Ai::Mission#scaling_bounds" do
    context "when the mission declares both bounds" do
      let(:watch_policies) do
        { "auto_scale_min_replicas" => 3, "auto_scale_max_replicas" => 9 }
      end

      it "reads the declaration off the mission's own configuration" do
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(3)
        expect(bounds.max).to eq(9)
        expect(bounds.auto_scale_out?).to be true
      end

      it "permits a replica count inside the window and refuses one outside it" do
        bounds = mission.scaling_bounds

        expect(bounds.permits_replica_count?(3)).to be true
        expect(bounds.permits_replica_count?(9)).to be true
        expect(bounds.permits_replica_count?(10)).to be false
        expect(bounds.permits_replica_count?(2)).to be false
      end
    end

    context "when the mission declares nothing" do
      it "falls back to the platform floor and leaves scale-out ineligible" do
        # The floor has a real default (the platform never scales to zero); the
        # CEILING has none — an undeclared ceiling must not license unattended
        # scale-out, which is exactly the fail-closed behaviour the bare
        # `auto_scale_max_replicas` read had.
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(Ai::Mission::DEFAULT_AUTO_SCALE_MIN_REPLICAS)
        expect(bounds.ceiling_declared?).to be false
        expect(bounds.auto_scale_out?).to be false
      end

      it "resolves a SiteSetting-supplied default rather than a hardcoded literal" do
        SiteSetting.set("ai.provisioning.auto_scale_min_replicas", 2, setting_type: "integer")
        SiteSetting.set("ai.provisioning.auto_scale_max_replicas", 6, setting_type: "integer")

        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(2)
        expect(bounds.max).to eq(6)
        expect(bounds.auto_scale_out?).to be true
      end
    end

    context "when the mission declares a bound over the SiteSetting default" do
      let(:watch_policies) { { "auto_scale_max_replicas" => 4 } }

      it "prefers the project's own declaration" do
        SiteSetting.set("ai.provisioning.auto_scale_max_replicas", 25, setting_type: "integer")

        expect(mission.scaling_bounds.max).to eq(4)
      end
    end

    context "when the declaration is incoherent" do
      let(:watch_policies) do
        { "auto_scale_min_replicas" => 8, "auto_scale_max_replicas" => 3 }
      end

      it "treats a floor above the ceiling as an EMPTY window, not a narrow one" do
        bounds = mission.scaling_bounds

        expect(bounds.coherent?).to be false
        expect(bounds.auto_scale_out?).to be false
        # The floor still stands for the destructive arm: refusing to remove is
        # never the dangerous direction.
        expect(bounds.min).to eq(8)
      end
    end

    context "when the mission declares nothing but its TEMPLATE does" do
      # Nothing merges Ai::MissionTemplate#default_configuration into a
      # mission's own configuration, so a bound seeded onto a project shape is
      # reachable only because #scaling_bounds reads the template rung.
      let(:mission) do
        template = create(:ai_mission_template, account: account,
                                                default_configuration: {
                                                  "watch_policies" => { "auto_scale_min_replicas" => 2,
                                                                        "auto_scale_max_replicas" => 7 }
                                                })
        m = create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                                mission_template: template,
                                configuration: { "brief" => { "scale" => { "initial" => 3 } } })
        m.update_columns(status: "active")
        m.reload
      end

      it "resolves the window off the template's default_configuration" do
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(2)
        expect(bounds.max).to eq(7)
        expect(bounds.auto_scale_out?).to be true
      end

      it "loses to the project's own declaration" do
        mission.update!(configuration: mission.configuration.merge(
          "watch_policies" => { "auto_scale_max_replicas" => 4 }
        ))

        expect(mission.reload.scaling_bounds.max).to eq(4)
      end
    end

    context "when only the ACCOUNT declares a bound" do
      it "sits between the project's own declaration and the SiteSetting" do
        account.update!(settings: { "ai.provisioning.auto_scale_max_replicas" => 6 })
        SiteSetting.set("ai.provisioning.auto_scale_max_replicas", 25, setting_type: "integer")

        expect(mission.scaling_bounds.max).to eq(6)
      end
    end

    context "when the mission declares an explicit ZERO ceiling" do
      let(:watch_policies) { { "auto_scale_max_replicas" => 0 } }

      it "stays fail-closed instead of inheriting a wider default" do
        # "0" is this model's own statement of "no ceiling, no unattended
        # scale-out". Falling through to the account or global rung would let a
        # platform-wide default silently overrule a project opting OUT — the one
        # direction a bounds ladder must never resolve.
        account.update!(settings: { "ai.provisioning.auto_scale_max_replicas" => 6 })
        SiteSetting.set("ai.provisioning.auto_scale_max_replicas", 25, setting_type: "integer")

        bounds = mission.scaling_bounds

        expect(bounds.max).to eq(0)
        expect(bounds.ceiling_declared?).to be false
        expect(bounds.auto_scale_out?).to be false
      end
    end

    context "when the configuration is held in memory with symbol keys" do
      it "still reads the declared floor" do
        # A missed floor removes MORE replicas, not fewer, so the reader must be
        # at least as tolerant as the AdaptationProposerService one it replaced
        # (which deep_stringify_keys first).
        in_memory = build(:ai_mission, account: account, created_by: user,
                                       mission_type: "infrastructure",
                                       configuration: { watch_policies: { auto_scale_min_replicas: 4 } })

        expect(in_memory.scaling_bounds.min).to eq(4)
      end
    end

    context "when the mission declares a floor below the platform minimum" do
      let(:watch_policies) do
        { "auto_scale_min_replicas" => 0, "auto_scale_max_replicas" => 5 }
      end

      it "never resolves a floor that would permit scaling to zero" do
        expect(mission.scaling_bounds.min).to eq(Ai::Mission::DEFAULT_AUTO_SCALE_MIN_REPLICAS)
      end
    end
  end

  # ------------------------------------------------------------------
  # 2. The composer's bounds verdict now reads that home
  # ------------------------------------------------------------------
  describe "Ai::Provisioning::AdaptationProposerService#auto_apply?" do
    subject(:service) do
      Ai::Provisioning::AdaptationProposerService.new(account: account, mission: mission)
    end

    def plan_with_step!(inputs)
      goal = Ai::AgentGoal.create!(
        account: account, agent: agent, title: "Adapt", goal_type: "improvement",
        status: "pending", priority: 3, progress: 0.0, success_criteria: {}, metadata: {}
      )
      plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft",
                                  version: 9, plan_data: { "kind" => "adaptation_diff" })
      Array(inputs).each_with_index do |cfg, idx|
        plan.steps.create!(step_number: idx + 1, step_type: "provisioning_skill", status: "pending",
                           description: "step", execution_config: cfg, dependencies: [])
      end
      plan
    end

    def scale_out_step(desired)
      { "skill" => "scale_project", "on_failure" => "rollback",
        "inputs" => { "change_type" => "scale_horizontal", "desired_replica_count" => desired,
                      "project_id" => mission.id, "target_count" => 1,
                      "scaling_strategy" => "add_replicas" } }
    end

    context "with a project-declared window" do
      let(:watch_policies) do
        { "auto_scale_min_replicas" => 2, "auto_scale_max_replicas" => 6 }
      end

      it "clears a scale-out that lands inside the declared window" do
        expect(service.auto_apply?(plan: plan_with_step!([ scale_out_step(6) ]))).to be true
      end

      it "refuses a scale-out that lands above the declared ceiling" do
        expect(service.auto_apply?(plan: plan_with_step!([ scale_out_step(7) ]))).to be false
      end

      it "refuses a REMOVAL regardless of the declared window" do
        # Ratified: destructive removals never auto-apply. Restated here as a
        # property of the BOUNDS arm — widening the window must not reach it.
        removal = { "skill" => "scale_project", "on_failure" => "rollback",
                    "inputs" => { "change_type" => "scale_horizontal", "project_id" => mission.id,
                                  "target_count" => 1, "scaling_strategy" => "remove_replicas" } }
        expect(service.auto_apply?(plan: plan_with_step!([ removal ]))).to be false
      end
    end

    context "with no project declaration and a SiteSetting default in place" do
      it "auto-applies within the operator's global default window" do
        SiteSetting.set("ai.provisioning.auto_scale_max_replicas", 6, setting_type: "integer")

        expect(service.auto_apply?(plan: plan_with_step!([ scale_out_step(5) ]))).to be true
        expect(service.auto_apply?(plan: plan_with_step!([ scale_out_step(7) ]))).to be false
      end
    end

    context "with no declaration anywhere" do
      it "stays fail-closed" do
        expect(service.auto_apply?(plan: plan_with_step!([ scale_out_step(4) ]))).to be false
      end
    end
  end
end
