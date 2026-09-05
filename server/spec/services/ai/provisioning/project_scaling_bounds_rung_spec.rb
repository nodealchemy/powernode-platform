# frozen_string_literal: true

require "rails_helper"

# APO increment `app-4-project-noun` — the PROJECT rung of the bounds ladder.
#
# APO-3a gave a scaling window one home and one walk (`Ai::Mission
# .resolve_scale_bound`), resolved mission `watch_policies` → mission TEMPLATE
# `default_configuration` → Account#settings → SiteSetting → constant. Now that
# a project is a real noun, it must be a RUNG in that ladder rather than a
# second, competing source of truth.
#
# WHERE the rung sits, and why: directly BELOW the mission's own declaration
# and ABOVE the mission template's. Below the mission because a mission is the
# more specific object — one project has many missions and a single mission may
# need a narrower window than its project. Above the TEMPLATE because the
# seeded `system_provisioning` template declares BOTH bounds (min 1 / max 5),
# so a project rung placed under it could never answer for any mission created
# through the provisioning flow — which is every mission a project owns. A rung
# that can never be reached for the priority use case is not a rung.
#
# SCALE-IN IS NEVER RELEASED BY BOUNDS. A project may RAISE its floor; it can
# never declare one that permits scaling below the platform minimum, and no
# window it declares reaches the removal arm.
RSpec.describe "Ai::Mission scaling bounds — the project rung", type: :model do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  let(:mission_watch_policies) { {} }
  let(:template_watch_policies) { {} }
  let(:project_configuration) { {} }

  let(:project) { create(:ai_project, account: account, configuration: project_configuration) }

  let(:mission_template) do
    create(:ai_mission_template,
           account: account,
           default_configuration: { "watch_policies" => template_watch_policies })
  end

  let(:mission) do
    create(:ai_mission,
           account: account,
           created_by: user,
           mission_type: "infrastructure",
           mission_template: mission_template,
           project: project,
           configuration: { "watch_policies" => mission_watch_policies })
  end

  describe "resolution order" do
    context "when only the PROJECT declares a window" do
      let(:project_configuration) do
        { "watch_policies" => { "auto_scale_min_replicas" => 2, "auto_scale_max_replicas" => 8 } }
      end

      it "resolves both bounds off the project" do
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(2)
        expect(bounds.max).to eq(8)
        expect(bounds.auto_scale_out?).to be true
      end
    end

    context "when the MISSION declares a window too" do
      let(:project_configuration) do
        { "watch_policies" => { "auto_scale_min_replicas" => 2, "auto_scale_max_replicas" => 8 } }
      end
      let(:mission_watch_policies) do
        { "auto_scale_min_replicas" => 4, "auto_scale_max_replicas" => 6 }
      end

      it "keeps the mission's own declaration decisive — the project is the FALLBACK" do
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(4)
        expect(bounds.max).to eq(6)
      end
    end

    context "when the mission TEMPLATE also declares a window" do
      let(:template_watch_policies) do
        { "auto_scale_min_replicas" => 1, "auto_scale_max_replicas" => 5 }
      end
      let(:project_configuration) do
        { "watch_policies" => { "auto_scale_min_replicas" => 3, "auto_scale_max_replicas" => 12 } }
      end

      it "puts the project ABOVE the template so the seeded shape cannot shadow it" do
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(3)
        expect(bounds.max).to eq(12)
      end
    end

    context "when the project declares only ONE half" do
      let(:template_watch_policies) do
        { "auto_scale_min_replicas" => 1, "auto_scale_max_replicas" => 5 }
      end
      let(:project_configuration) do
        { "watch_policies" => { "auto_scale_max_replicas" => 20 } }
      end

      it "resolves each bound independently — the undeclared half falls through" do
        bounds = mission.scaling_bounds

        expect(bounds.max).to eq(20)
        expect(bounds.min).to eq(1)
      end
    end

    context "when the mission has NO project" do
      let(:template_watch_policies) do
        { "auto_scale_min_replicas" => 1, "auto_scale_max_replicas" => 5 }
      end

      let(:mission) do
        create(:ai_mission,
               account: account,
               created_by: user,
               mission_type: "infrastructure",
               mission_template: mission_template,
               configuration: { "watch_policies" => {} })
      end

      it "resolves exactly as it did before the rung existed" do
        expect(mission.project).to be_nil

        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(1)
        expect(bounds.max).to eq(5)
      end
    end
  end

  describe "the utilization ladder gains the same rung" do
    let(:project_configuration) do
      { "slo_targets" => { "max_cpu_pct" => 65, "max_memory_pct" => 80 } }
    end

    it "resolves a project-declared ceiling" do
      targets = mission.utilization_targets

      expect(targets.cpu_pct).to eq(65.0)
      expect(targets.memory_pct).to eq(80.0)
    end

    it "keeps the mission's own slo_targets decisive" do
      mission.update!(configuration: mission.configuration.merge(
        "slo_targets" => { "max_cpu_pct" => 90 }
      ))

      expect(mission.reload.utilization_targets.cpu_pct).to eq(90.0)
    end
  end

  describe "scale-IN is never released by a project bound" do
    context "when the project declares a floor of zero" do
      let(:project_configuration) do
        { "watch_policies" => { "auto_scale_min_replicas" => 0, "auto_scale_max_replicas" => 9 } }
      end

      it "clamps the floor UP to the platform minimum — a project cannot license scaling to zero" do
        bounds = mission.scaling_bounds

        expect(bounds.min).to eq(Ai::Mission::DEFAULT_AUTO_SCALE_MIN_REPLICAS)
        expect(bounds.min).to eq(1)
        expect(bounds.permits_replica_count?(0)).to be false
      end
    end

    context "when the project declares a WIDE window" do
      let(:project_configuration) do
        { "watch_policies" => { "auto_scale_min_replicas" => 1, "auto_scale_max_replicas" => 50 } }
      end

      it "cannot make a REMOVAL step auto-applicable" do
        # The composer's auto-apply verdict is an allowlist of the one ADDITIVE
        # strategy, checked after the bounds window. Widening the window through
        # the new project rung must not reach the removal arm.
        agent = create(:ai_agent, account: account)
        goal = Ai::AgentGoal.create!(
          account: account, agent: agent, title: "Adapt", goal_type: "improvement",
          status: "pending", priority: 3, progress: 0.0, success_criteria: {},
          metadata: { "provisioning_mission_id" => mission.id }
        )
        plan = Ai::GoalPlan.create!(
          account: account, goal: goal, agent: agent, status: "draft",
          version: 1, plan_data: { "kind" => "adaptation_diff" }
        )
        plan.steps.create!(
          step_number: 1, step_type: "provisioning_skill", status: "pending",
          description: "remove replicas", dependencies: [],
          execution_config: {
            "skill" => "scale_project",
            "inputs" => {
              "change_type" => "scale_horizontal",
              "scaling_strategy" => "remove_replicas",
              "target_count" => 2,
              "desired_replica_count" => 2
            }
          }
        )

        service = Ai::Provisioning::AdaptationProposerService.new(account: account, mission: mission)

        expect(mission.scaling_bounds.auto_scale_out?).to be true
        expect(mission.scaling_bounds.permits_replica_count?(2)).to be true
        expect(service.auto_apply?(plan: plan)).to be false
      end
    end
  end
end
